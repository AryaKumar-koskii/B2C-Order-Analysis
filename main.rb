require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'

def main
  begin
    # Step 1: Load the location alias mapping
    puts "Loading location alias mapping..."
    Location.load_locations('../csv_files/location_alias_mapping.csv')

    # Step 2: Load pending forwards
    puts "Loading pending forwards..."
    PendingForward.load_from_csv('../csv_files/pending_forwards.csv')

    # Step 3: Load forward shipments (only pending)
    puts "Loading forward shipments..."
    ForwardShipment.read_from_csv('../csv_files/WMS_SFS_merged_data(for_analysis).csv')

    # Step 4: Load return shipments
    puts "Loading return shipments..."
    ReturnShipment.read_from_csv('../csv_files/ReturnOrderItemLevelReport.csv')

    # Step 5: Load barcode location data
    puts "Loading barcode location data..."
    BarcodeLocation.read_from_csv('../csv_files/barcode_location.csv')

    puts "Data loading completed successfully!"

    valid_orders = get_valid_forward_orders_with_returns
    p "valid_orders with returns"
    valid_orders.each { |valid_order|
      p valid_order
    }
    p "------------------------------------------------------------------------------"

    sto_orders = get_orders_with_wrong_barcode_location_with_returns
    p "orders with barcode at diff location with returns"
    sto_orders.each do |order|
      p order
    end
    p "------------------------------------------------------------------------------"

    write_all_read_forwards

    valid_orders_without_returns = get_orders_without_returns_at_right_location
    p "valid_orders with out returns"
    valid_orders_without_returns.each do |order|
      p order
    end
    p "------------------------------------------------------------------------------"

    sto_orders_without_returns = get_partial_valid_orders_without_returns
    p "partial valid_orders with out returns"
    sto_orders_without_returns.each do |order|
      p order
    end
    p "------------------------------------------------------------------------------"

    p "barcodes with invalid characteristics"
    barcodes_in_fulfilment_location_and_in_other_location
    p "------------------------------------------------------------------------------"
  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

def valid_forward_shipment?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    if return_shipments.empty?
      return false
    end

    # Iterate over all matching return shipments
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.sku == shipment_line.sku && line.barcode == shipment_line.barcode }
    end
    unless matching_return_found
      return false
    end

    # Condition 2: Barcode location should match the fulfillment location
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations && barcode_locations.all? { |bl| bl.location == shipment_line.fulfilment_location }
      return false
    end

    # Condition 3: Validate quantity for the barcode in the location
    barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
    unless barcode_location && barcode_location.quantity == 1
      return false
    end

    # Condition 4: Ensure barcode is not associated with more than one shipment
    # barcode_used_in_multiple_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
    # next if barcode_used_in_multiple_shipments

    # Condition 5: Ensure return exists at barcode level for any of the return shipments
    return_shipment_barcode_match = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.barcode == shipment_line.barcode }
    end
    unless return_shipment_barcode_match
      return false
    end
  end
  true
end

def partial_valid_shipment?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    if return_shipments.empty?
      return false
    end

    # Get all locations for the barcode
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations
      return false
    end

    # Ensure that at least one return shipment matches the barcode
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.any? { |line| line.barcode == shipment_line.barcode }
    end
    unless matching_return_found
      return false
    end

    if barcode_locations.size > 1 && barcode_locations.none? { |bl| bl.quantity == 0 }
      return false
    end

    if barcode_locations.size > 1
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
        return false
      end
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    unless valid_quantity_location
      return false
    end
  end
  true
end

def barcodes_in_fulfilment_location_and_in_other_location
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations
        next
      end

      if barcode_locations.size > 1 && barcode_locations.none? { |bl| bl.quantity == 0 }
        next
      end

      if barcode_locations.size > 1
        barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
        if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
          p shipment_line.barcode
        end
      end
    end
  end
end

def valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    unless get_valid_barcode_location(shipment_line)
      return false
    end

    if ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
      return false
    end
  end
  true
end

def partial_valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations
      return false
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    unless valid_quantity_location
      return false
    end
  end
  true
end

def get_partial_valid_barcodes(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  barcode_location = barcode_locations.find { |bl| bl.quantity == 1 }
  barcode_location if barcode_location
end

def write_orders_to_text_file(valid_orders, file_name)
  File.open(file_name, "w") do |file|
    # Write a header line
    file.puts "Fulfilment Location,Parent Order Code,Shipment ID,Barcode,SKU,Barcode Location,Quantity"

    # Write each valid order
    valid_orders.each do |order|
      file.puts "#{order[:fulfilment_location]},#{order[:parent_order_code]},#{order[:shipment_id]},#{order[:barcode]},#{order[:sku]},#{order[:barcode_location]},#{order[:quantity]}"
    end
  end
end

def get_valid_barcode_location(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  return false unless barcode_locations
  barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
  barcode_location if barcode_location && barcode_location.quantity == 1
end

def get_valid_forward_orders_with_returns

  valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|

    valid_forward = valid_forward_shipment?(forward_shipment)
    next unless valid_forward

    forward_shipment.shipment_lines.each do |shipment_line|

      barcode_location = get_valid_barcode_location(shipment_line)
      next unless barcode_location

      # If all conditions match, add to valid_orders
      valid_orders << {
        fulfilment_location: shipment_line.fulfilment_location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: shipment_line.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
        barcode_location: barcode_location.location,
        quantity: barcode_location.quantity
      }
    end
  end

  write_orders_to_text_file(valid_orders, '../results/valid_orders.csv')
  valid_orders
end

def get_orders_with_wrong_barcode_location_with_returns
  partial_availability_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    all_barcodes_available = partial_valid_shipment?(forward_shipment)

    # If any barcode in the shipment is not available, skip this shipment
    next unless all_barcodes_available

    # All barcodes are available, so collect the data
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_partial_valid_barcodes(shipment_line)

      next unless barcode_location
      partial_availability_orders << {
        fulfilment_location: shipment_line.fulfilment_location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: shipment_line.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
        barcode_location: barcode_location.location, # Use the valid location
        quantity: barcode_location.quantity
      }
    end
  end

  # Write the orders to a text file
  write_orders_to_text_file(partial_availability_orders, '../results/partial_availability_orders.csv')
  partial_availability_orders
end

def get_orders_without_returns_at_right_location
  forwards_without_returns = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    valid_forward = valid_shipment_without_returns?(forward_shipment)

    next unless valid_forward

    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_valid_barcode_location(shipment_line)
      next unless barcode_location

      # If all conditions match, add to valid_orders
      forwards_without_returns << {
        fulfilment_location: shipment_line.fulfilment_location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: shipment_line.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
        barcode_location: barcode_location.location,
        quantity: barcode_location.quantity
      }

    end
  end

  write_orders_to_text_file(forwards_without_returns, '../results/forwards_without_returns.csv')
  forwards_without_returns
end

def get_partial_valid_orders_without_returns
  partial_valid_orders = []
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|

    valid_forward = partial_valid_shipment_without_returns?(forward_shipment)
    next unless valid_forward

    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_partial_valid_barcodes(shipment_line)

      next unless barcode_location
      partial_valid_orders << {
        fulfilment_location: shipment_line.fulfilment_location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: shipment_line.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
        barcode_location: barcode_location.location, # Use the valid location
        quantity: barcode_location.quantity
      }
    end
  end

  write_orders_to_text_file(partial_valid_orders, '../results/partial_valid_orders_without_returns.csv')
  partial_valid_orders
end

def write_all_read_forwards
  all_forwards = []
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    forward_shipment.shipment_lines.each do |shipment_line|
      all_forwards << {
        fulfilment_location: shipment_line.fulfilment_location,
        parent_order_code: forward_shipment.parent_order_id,
        shipment_id: shipment_line.shipment_id,
        sku: shipment_line.sku,
        barcode: shipment_line.barcode,
      }
    end
  end
  write_orders_to_text_file(all_forwards, '../results/read_forwards.csv')
end

# Run the main method
main