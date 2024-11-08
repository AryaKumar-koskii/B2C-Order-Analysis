require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'
require 'csv'
require 'fileutils'
require_relative 'file_merger'

def load_files
  @project_root = File.expand_path("..", __dir__)
  puts 'Loading location alias mapping...'
  Location.load_locations("#{@project_root}/csv_files/location_alias_mapping.csv")

  puts 'Loading pending forwards...'
  PendingForward.load_from_csv("#{@project_root}/csv_files/pending_forwards.csv")

  puts 'Loading forward shipments...'
  ForwardShipment.read_from_csv("#{@project_root}/csv_files/new_merged/forward_order.csv")

  puts 'Loading return shipments...'
  ReturnShipment.read_from_csv("#{@project_root}/csv_files/new_merged/return_order.csv")

  puts 'Loading barcode location data...'
  BarcodeLocation.read_from_csv("#{@project_root}/csv_files/barcode_location.csv")

  puts 'Data loading completed successfully!'
end

def main
  project_root = File.expand_path("..", __dir__)
  file_merger = FileMerger.new(project_root)
  needs_merge = false

  begin
    file_merger.merge_return_order_files if needs_merge
    file_merger.merge_order_files if needs_merge

    load_files

    process_valid_orders_with_returns
    process_orders_with_wrong_barcode_location_with_returns
    process_valid_orders_without_returns
    process_partial_valid_orders_without_returns

    puts 'Processing completed successfully!'
  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

def process_valid_orders_with_returns
  puts 'Processing valid orders with returns...'
  valid_orders = get_valid_forward_orders_with_returns
  valid_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_orders_with_wrong_barcode_location_with_returns
  puts 'Processing orders with barcode in different location with returns...'
  sto_orders = get_orders_with_wrong_barcode_location_with_returns
  sto_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_valid_orders_without_returns
  puts 'Processing valid orders without returns...'
  valid_orders_without_returns = get_orders_without_returns_at_right_location
  valid_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_partial_valid_orders_without_returns
  puts 'Processing partial valid orders without returns...'
  sto_orders_without_returns = get_partial_valid_orders_without_returns
  sto_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def valid_forward_shipment?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    return false if return_shipments.empty?

    forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    return false unless forward_shipments.count > 1

    # Iterate over all matching return shipments
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.sku == shipment_line.sku && line.barcode == shipment_line.barcode }
    end
    return false unless matching_return_found

    # Condition 2: Barcode location should match the fulfillment location
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations && barcode_locations.all? { |bl| bl.location == shipment_line.fulfilment_location }
      return false
    end

    # Condition 3: Validate quantity for the barcode in the location
    barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
    return false unless barcode_location && barcode_location.quantity == 1

    # Condition 4: Ensure barcode is not associated with more than one shipment
    # barcode_used_in_multiple_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
    # next if barcode_used_in_multiple_shipments

    # Condition 5: Ensure return exists at barcode level for any of the return shipments
    return_shipment_barcode_match = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.barcode == shipment_line.barcode }
    end
    return false unless return_shipment_barcode_match
  end
  true
end

def partial_valid_shipment?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    return false if return_shipments.empty?

    forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    return false unless forward_shipments.count > 1

    # Get all locations for the barcode
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations

    # Ensure that at least one return shipment matches the barcode
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.any? { |line| line.barcode == shipment_line.barcode }
    end
    return false unless matching_return_found

    return false if barcode_locations.size > 1 && barcode_locations.none? { |bl| bl.quantity == 0 }

    if barcode_locations.size > 1
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      return false if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    return false unless valid_quantity_location
  end
  true
end

def partial_valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|

    return false if shipment_line.barcode.nil?

    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations

    forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    return false unless forward_shipments.count > 1

    if barcode_locations.size > 1
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      return false if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    return false unless valid_quantity_location
  end
  true
end

def valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    return false unless get_valid_barcode_location(shipment_line)

    return false if ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
  end
  true
end

def get_valid_barcode_location(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  return false unless barcode_locations
  barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
  barcode_location if barcode_location && barcode_location.quantity == 1
end

def get_partial_valid_barcodes(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  barcode_location = barcode_locations.find { |bl| bl.quantity == 1 }
  barcode_location if barcode_location
end

def get_valid_forward_orders_with_returns
  valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    if valid_forward_shipment?(forward_shipment)
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = get_valid_barcode_location(shipment_line)
        if barcode_location
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
    end
  end

  write_orders_to_text_file(valid_orders, "#{@project_root}/results/valid_orders.csv")
  valid_orders
end

def get_orders_with_wrong_barcode_location_with_returns
  partial_availability_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    if partial_valid_shipment?(forward_shipment)
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = get_partial_valid_barcodes(shipment_line)
        if barcode_location
          partial_availability_orders << {
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
    end
  end

  write_orders_to_text_file(partial_availability_orders, "#{@project_root}/results/partial_availability_orders.csv")
  partial_availability_orders
end

def get_orders_without_returns_at_right_location
  forwards_without_returns = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    if valid_shipment_without_returns?(forward_shipment)
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = get_valid_barcode_location(shipment_line)
        if barcode_location
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
    end
  end

  write_orders_to_text_file(forwards_without_returns, "#{@project_root}/results/forwards_without_returns.csv")
  forwards_without_returns
end

def get_partial_valid_orders_without_returns
  partial_valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    if partial_valid_shipment_without_returns?(forward_shipment)
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = get_partial_valid_barcodes(shipment_line)
        if barcode_location
          partial_valid_orders << {
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
    end
  end

  write_orders_to_text_file(partial_valid_orders, "#{@project_root}/results/partial_valid_orders_without_returns.csv")
  partial_valid_orders
end

def write_orders_to_text_file(orders, file_name)
  File.open(file_name, 'w') do |file|
    file.puts 'Fulfilment Location,Parent Order Code,Shipment ID,Barcode,SKU,Barcode Location,Quantity'
    orders.each do |order|
      file.puts "#{order[:fulfilment_location]},#{order[:parent_order_code]},#{order[:shipment_id]},#{order[:barcode]},#{order[:sku]},#{order[:barcode_location]},#{order[:quantity]}"
    end
  end
end

main
