require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'

def main
  begin
    # Step 1: Load the location alias mapping
    puts "Loading location alias mapping..."
    Location.load_locations('csv_files/location_alias_mapping.csv')

    # Step 2: Load pending forwards
    puts "Loading pending forwards..."
    PendingForward.load_from_csv('csv_files/pending_forwards.csv')

    # Step 3: Load forward shipments (only pending)
    puts "Loading forward shipments..."
    ForwardShipment.read_from_csv('csv_files/WMS_SFS_merged_data(for_analysis).csv')

    # Step 4: Load return shipments
    puts "Loading return shipments..."
    ReturnShipment.read_from_csv('csv_files/ReturnOrderItemLevelReport.csv')

    # Step 5: Load barcode location data
    puts "Loading barcode location data..."
    BarcodeLocation.read_from_csv('csv_files/barcode_location.csv')

    puts "Data loading completed successfully!"

    valid_orders = get_valid_forward_orders
    valid_orders.each { |valid_order|
      p valid_order
    }

    sto_orders = get_partial_barcode_availability

    # Example queries:
    # Find a forward shipment by shipment ID
    # forward_shipment = ForwardShipment.find_by_shipment_id('136635')
    # if forward_shipment
    #   puts "Forward Shipment found: #{forward_shipment.forward_order_id}"
    # else
    #   puts "Forward Shipment not found for KO202061"
    # end
    #
    # # find barcodes for which the quantities are >1 and <0
    # BarcodeLocation.find_barcodes_with_invalid_quantities
    #
    # forward_shipment.barcode_in_same_location?
    # forward_shipment.barcode_in_other_location?
    #
    # ForwardShipment.find_barcodes_in_multiple_shipments
    #
    # BarcodeLocation.barcode_returned?
    #
    # # Find all forward shipments containing a specific barcode
    # shipments_by_barcode = ForwardShipment.find_by_barcode('K988505')
    # puts "Shipments with barcode 'k948612': #{shipments_by_barcode.inspect}"
    #
    # # Find all forward shipments without any return shipments
    # shipments_without_returns = ForwardShipment.find_without_return_shipments
    # puts "Forward shipments without returns: #{shipments_without_returns.inspect}"
    #
    # # Find all pending forward shipments
    # pending_forward_shipments = ForwardShipment.all.select { |fs| fs.pending }
    # puts "Pending Forward Shipments: #{pending_forward_shipments.inspect}"

  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

def get_valid_forward_orders
  valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    valid_forward = true
    forward_shipment.shipment_lines.each do |shipment_line|
      # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
      return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
      if return_shipments.empty?
        valid_forward = false
        break
      end

      # Iterate over all matching return shipments
      matching_return_found = return_shipments.any? do |return_shipment|
        return_shipment.shipment_lines.all? { |line| line.sku == shipment_line.sku && line.barcode == shipment_line.barcode }
      end
      unless matching_return_found
        valid_forward = false
        break
      end

      # Condition 2: Barcode location should match the fulfillment location
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations && barcode_locations.all? { |bl| bl.location == shipment_line.fulfilment_location }
        valid_forward = false
        break
      end

      # Condition 3: Validate quantity for the barcode in the location
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      unless barcode_location && barcode_location.quantity == 1
        valid_forward = false
        break
      end

      # Condition 4: Ensure barcode is not associated with more than one shipment
      # barcode_used_in_multiple_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
      # next if barcode_used_in_multiple_shipments

      # Condition 5: Ensure return exists at barcode level for any of the return shipments
      return_shipment_barcode_match = return_shipments.any? do |return_shipment|
        return_shipment.shipment_lines.all? { |line| line.barcode == shipment_line.barcode }
      end
      unless return_shipment_barcode_match
        valid_forward = false
        break
      end
    end

    if valid_forward
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
        barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
        # If all conditions match, add to valid_orders
        valid_orders << {
          fulfilment_location: shipment_line.fulfilment_location,
          parent_order_code: forward_shipment.parent_order_id,
          shipment_id: forward_shipment.shipment_id,
          sku: shipment_line.sku,
          barcode: shipment_line.barcode,
          barcode_location: barcode_location.location,
          quantity: barcode_location.quantity
        }
      end
    end
  end

  write_orders_to_text_file(valid_orders, 'valid_orders.csv')
  valid_orders
end

def get_partial_barcode_availability
  partial_availability_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    all_barcodes_available = true

    forward_shipment.shipment_lines.each do |shipment_line|
      # Get all locations for the barcode
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations
        all_barcodes_available = false
        next
      end

      # Validate if the barcode has a valid quantity in any location
      valid_quantity_location = barcode_locations.any? { |bl| bl.quantity == 1 }
      unless valid_quantity_location
        all_barcodes_available = false
        break
      end
    end

    # If any barcode in the shipment is not available, skip this shipment
    next unless all_barcodes_available

    # Check if all barcodes in the forward shipment have been returned
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    next if return_shipments.empty?

    all_barcodes_returned = return_shipments.any? do |return_shipment|
      forward_shipment.shipment_lines.all? do |shipment_line|
        return_shipment.shipment_lines.any? { |line| line.barcode == shipment_line.barcode }
      end
    end
    next unless all_barcodes_returned

    # If all conditions are met, add the forward shipment details to the result
    forward_shipment.shipment_lines.each do |shipment_line|
      partial_availability_orders << {
        fulfilment_location: forward_shipment.location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: forward_shipment.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
        barcode_location: BarcodeLocation.find_by_barcode(shipment_line.barcode).first.location # Use any valid location
      }
    end
  end

  partial_availability_orders
end

def write_orders_to_text_file(valid_orders, file_name)
  File.open(file_name, "w") do |file|
    # Write a header line
    file.puts "Fulfilment Location, Parent Order Code, Shipment ID, Barcode, Barcode Location, Quantity"

    # Write each valid order
    valid_orders.each do |order|
      file.puts "#{order[:fulfilment_location]}, #{order[:parent_order_code]}, #{order[:shipment_id]}, #{order[:barcode]}, #{order[:barcode_location]}, #{order[:quantity]}"
    end
  end
end

# Run the main method
main