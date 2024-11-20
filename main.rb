require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'order_shipment_data'
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

  p 'Loading completed shipments data...'
  OrderShipmentData.read_from_csv("#{@project_root}/csv_files/order_shipment_data.csv")

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
    process_valid_orders_with_returns_at_shipment_level
    process_orders_with_wrong_barcode_location_with_returns_at_shipment_level
    process_valid_orders_without_returns_at_shipment_level

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

def process_valid_orders_with_returns_at_shipment_level
  puts 'Processing valid orders with returns at shipment level...'
  valid_orders = get_valid_forward_orders_with_returns(true)
  valid_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_orders_with_wrong_barcode_location_with_returns_at_shipment_level
  puts 'Processing orders with barcode in different location with returns at shipment level...'
  sto_orders = get_orders_with_wrong_barcode_location_with_returns(true)
  sto_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_valid_orders_without_returns_at_shipment_level
  puts 'Processing valid orders without returns at shipment level...'
  valid_orders_without_returns = get_orders_without_returns_at_right_location(true)
  valid_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_partial_valid_orders_without_returns_at_shipment_level
  puts 'Processing partial valid orders without returns at shipment level...'
  sto_orders_without_returns = get_partial_valid_orders_without_returns(true)
  sto_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def valid_forward_shipment?(forward_shipment, is_shipment_level = false)
  valid_shipments = []
  forward_shipment.shipment_lines.each do |shipment_line|
    # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    # p return_shipments unless return_shipments.empty?
    if return_shipments.empty?
      next if is_shipment_level
      return false
    end

    # forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    # unless forward_shipments.count > 1
    #   next if is_shipment_level
    #   return false
    # end

    # Iterate over all matching return shipments
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.sku == shipment_line.sku && line.barcode == shipment_line.barcode }
    end
    unless matching_return_found
      next if is_shipment_level
      return false
    end

    # Condition 2: Barcode location should match the fulfillment location
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations && barcode_locations.all? { |bl| bl.location == shipment_line.fulfilment_location }
      next if is_shipment_level
      return false
    end

    # Condition 3: Validate quantity for the barcode in the location
    barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
    unless barcode_location && barcode_location.quantity == 1
      next if is_shipment_level
      return false
    end

    # Condition 5: Ensure return exists at barcode level for any of the return shipments
    return_shipment_barcode_match = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.all? { |line| line.barcode == shipment_line.barcode }
    end
    unless return_shipment_barcode_match
      next if is_shipment_level
      return false
    end

    valid_shipments << shipment_line.shipment_id

  end
  return true unless is_shipment_level
  return false if valid_shipments.empty?

  valid_shipments
end

def partial_valid_shipment?(forward_shipment, is_shipment_level = false)
  valid_shipments = []
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    if return_shipments.empty?
      next if is_shipment_level
      return false
    end

    forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    unless forward_shipments.count > 1
      next if is_shipment_level
      return false
    end

    # Get all locations for the barcode
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations
      next if is_shipment_level
      return false
    end

    # Ensure that at least one return shipment matches the barcode
    matching_return_found = return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.any? { |line| line.barcode == shipment_line.barcode }
    end
    unless matching_return_found
      next if is_shipment_level
      return false
    end

    if barcode_locations.size > 1
      if barcode_locations.none? { |bl| bl.quantity == 0 }
        next if is_shipment_level
        return false
      end

      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
        next if is_shipment_level
        return false
      end
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    unless valid_quantity_location
      next if is_shipment_level
      return false
    end

    valid_shipments << shipment_line.shipment_id
  end

  return true unless is_shipment_level
  return false if valid_shipments.empty?

  valid_shipments
end

def partial_valid_shipment_without_returns?(forward_shipment, is_shipment_level = false)
  valid_shipments = []
  forward_shipment.shipment_lines.each do |shipment_line|
    return false if shipment_line.barcode.nil?

    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    unless barcode_locations
      next if is_shipment_level
      return false
    end

    forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
    unless forward_shipments.count > 1
      next if is_shipment_level
      return false
    end

    if barcode_locations.size > 1
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
        next if is_shipment_level
        return false
      end
    end

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    unless valid_quantity_location
      next if is_shipment_level
      return false
    end

    valid_shipments << forward_shipment
  end

  return true unless is_shipment_level
  return false if valid_shipments.empty?

  valid_shipments
end

def valid_shipment_without_returns?(forward_shipment, is_shipment_level = false)
  valid_shipments = []
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for valid barcode locations
    unless get_valid_barcode_location(shipment_line)
      next if is_shipment_level
      return false
    end

    # Check if the barcode is associated with multiple shipments
    if ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
      next if is_shipment_level
      return false
    end

    valid_shipments << shipment_line.shipment_id
  end

  return true unless is_shipment_level
  return false if valid_shipments.empty?

  valid_shipments
end

def get_valid_barcode_location(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  return false unless barcode_locations
  barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
  barcode_location if barcode_location && barcode_location.quantity == 1
end

def get_partial_valid_barcodes(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  return false unless barcode_locations
  barcode_location = barcode_locations.find { |bl| bl.quantity == 1 }
  barcode_location if barcode_location
end

def get_valid_forward_orders_with_returns(is_shipment_level = false)
  valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    shipments = valid_forward_shipment?(forward_shipment, is_shipment_level)
    next unless shipments
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_valid_barcode_location(shipment_line)
      next unless barcode_location
      if is_shipment_level and shipments.include?(shipment_line.shipment_id)
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

  file_name = "#{@project_root}/results/valid_orders#{'(shipment_level)' if is_shipment_level}.csv"
  write_orders_to_text_file(valid_orders, file_name)
  valid_orders
end

def get_orders_with_wrong_barcode_location_with_returns(is_shipment_level = false)
  partial_availability_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    shipment = partial_valid_shipment?(forward_shipment, is_shipment_level)
    next unless shipment
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_partial_valid_barcodes(shipment_line)
      next unless barcode_location
      if is_shipment_level and shipment.include?(shipment_line.shipment_id)
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

  file_name = "#{@project_root}/results/partial_availability_orders.csv#{'(shipment_level)' if is_shipment_level}.csv"
  write_orders_to_text_file(partial_availability_orders, file_name)
  partial_availability_orders
end

def get_orders_without_returns_at_right_location(is_shipment_level = false)
  forwards_without_returns = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    shipments = valid_shipment_without_returns?(forward_shipment, is_shipment_level)
    next unless shipments
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_valid_barcode_location(shipment_line)
      next unless barcode_location
      if is_shipment_level and shipments.include?(shipment_line.shipment_id)
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

  file_name = "#{@project_root}/results/forwards_without_returns#{'(shipment_level)' if is_shipment_level}.csv"

  write_orders_to_text_file(forwards_without_returns, file_name)
  forwards_without_returns
end

def get_partial_valid_orders_without_returns(is_shipment_level = false)
  partial_valid_orders = []

  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    shipment = partial_valid_shipment_without_returns?(forward_shipment, is_shipment_level)
    next unless shipment
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_location = get_partial_valid_barcodes(shipment_line)
      next unless barcode_location
      if is_shipment_level and shipments.include?(shipment_line.shipment_id)
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
