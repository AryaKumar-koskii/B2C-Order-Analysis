require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'
require 'csv'
require 'fileutils'



def load_files
  @project_root = File.expand_path("..", __dir__)
  puts 'Loading location alias mapping...'
  Location.load_locations("#{@project_root}/csv_files/location_alias_mapping.csv")

  # Step 2: Load pending forwards
  puts 'Loading pending forwards...'
  PendingForward.load_from_csv("#{@project_root}/csv_files/pending_forwards.csv")

  # Step 3: Load forward shipments (only pending)
  puts 'Loading forward shipments...'
  ForwardShipment.read_from_csv("#{@project_root}/csv_files/new_merged/forward_order.csv")

  # Step 4: Load return shipments
  puts 'Loading return shipments...'
  ReturnShipment.read_from_csv("#{@project_root}/csv_files/new_merged/return_order.csv")

  # Step 5: Load barcode location data
  puts 'Loading barcode location data...'
  BarcodeLocation.read_from_csv("#{@project_root}/csv_files/barcode_location.csv")

  puts 'Data loading completed successfully!'
end


def process_csv_files(input_directory, output_file, required_columns, filter_conditions)
  unless Dir.exist?(input_directory)
    puts "Input directory does not exist: #{input_directory}"
    return []
  end

  puts 'Files in input directory:'
  Dir.entries(input_directory).each { |entry| puts entry }

  csv_files = Dir.glob(File.join(input_directory, '*.csv'))
  return [] if csv_files.empty?

  puts 'CSV files to be processed:'
  csv_files.each { |file| puts file }

  filtered_rows = []

  csv_files.each do |file|
    begin
      csv_data = CSV.read(file, headers: true)
    rescue StandardError => e
      puts "Error reading #{file}: #{e.message}"
      next
    end

    unless (required_columns - csv_data.headers).empty?
      puts "Skipping #{file}: Missing one of the required columns #{required_columns}"
      next
    end

    csv_data.each do |row|
      filtered_rows << row.to_hash if filter_conditions.call(row)
    end
  end


  if filtered_rows.empty?
    puts 'No data matched the filter conditions.'
  else
    FileUtils.mkdir_p(File.dirname(output_file)) unless Dir.exist?(File.dirname(output_file))
    CSV.open(output_file, 'w', write_headers: true, headers: filtered_rows.first.keys) do |csv|
      filtered_rows.each { |row| csv << row.values }
    end

    puts "\nFiltered data has been saved to '#{output_file}'"
    puts "\nTotal number of rows in the combined data: #{filtered_rows.size}"
  end

  filtered_rows.size
end

def merge_shipped_order
  project_root = '..'
  input_directory = File.join(project_root, 'csv_files', 'WMS_outward')
  output_file = File.join(project_root, 'csv_files/new_merged', 'WMS_outward.csv')

  required_columns = ['Pack Type', 'Order Type']
  filter_conditions = ->(row) { row['Pack Type'] == 'B2C' && row['Order Type'] == 'SALES' }

  process_csv_files(input_directory, output_file, required_columns, filter_conditions)
end

def merge_sfs_order
  project_root = '..'
  input_directory = File.join(project_root, 'csv_files', 'SFS_outward')
  output_file = File.join(project_root, 'csv_files/new_merged', 'SFS_outward.csv')

  required_columns = ['Channel ID', 'SFS/USP Order Status']
  filter_conditions = ->(row) { row['Channel ID'] != 'SHOPIFYUS' && ['PACKED', 'COMPLETED', 'PICKING_COMPLETED'].include?(row['SFS/USP Order Status']) }

  process_csv_files(input_directory, output_file, required_columns, filter_conditions)
end

def merge_return_order_files
  project_root = '..'
  input_directory = File.join(project_root, 'csv_files', 'return_order')
  output_file = File.join(project_root, 'csv_files/new_merged', 'return_order.csv')

  nil unless process_csv_files(input_directory, output_file, [], ->(_row) { true }).positive?
end

def merge_order_files
  merge_shipped_order
  merge_sfs_order
  file1_path = '../csv_files/new_merged/SFS_outward.csv'
  file2_path = '../csv_files/new_merged/WMS_outward.csv'
  output_file = '../csv_files/new_merged/forward_order.csv'

  begin
    df1 = CSV.read(file1_path, headers: true).map(&:to_hash)
    df2 = CSV.read(file2_path, headers: true).map(&:to_hash)
  rescue StandardError => e
    puts "Error reading files: #{e.message}"
    return
  end

  # Rename columns in File 1 to match File 2
  df1.each do |row|
    row['Fulfilment Location Name'] = row.delete('fulfillment_location_name') if row.key?('fulfillment_location_name')
    row['External Item Code'] = row.delete('External Item ID') if row.key?('External Item ID')
    row['Sales Channel'] = row.delete('Channel ID') if row.key?('Channel ID')
    row['Client SKU ID / EAN'] = row.delete('Client SKU ID') if row.key?('Client SKU ID')
    row['Parent Order ID'] = nil # Initialize 'Parent Order ID' with nil values
  end

  columns_to_keep = [
    'Fulfilment Location Name',
    'Channel Order ID',
    'Parent Order ID',
    'Shipment ID',
    'External Item Code',
    'Client SKU ID / EAN',
    'Sales Channel'
  ]

  # Select and merge data
  merged_df = (df1 + df2).map { |row| row.slice(*columns_to_keep) }.uniq
  merged_df.reject! { |row| row['Channel Order ID'].nil? || row['Shipment ID'].nil? }

  # Write merged data to a new CSV file
  CSV.open(output_file, 'w', write_headers: true, headers: columns_to_keep) do |csv|
    merged_df.each { |row| csv << row.values }
  end

  puts "\nMerged data has been saved to '#{output_file}'"
end

def main
  needs_merge = FALSE
  begin
    if needs_merge
      merge_return_order_files
      merge_order_files
    end
    load_files

    valid_orders = get_valid_forward_orders_with_returns
    p 'valid_orders with returns'
    valid_orders.each { |valid_order|
      p valid_order
    }
    p '------------------------------------------------------------------------------'

    sto_orders = get_orders_with_wrong_barcode_location_with_returns
    p 'orders with barcode at diff location with returns'
    sto_orders.each do |order|
      p order
    end
    p '------------------------------------------------------------------------------'

    write_all_read_forwards

    valid_orders_without_returns = get_orders_without_returns_at_right_location
    p 'valid_orders with out returns'
    valid_orders_without_returns.each do |order|
      p order
    end
    p '------------------------------------------------------------------------------'

    sto_orders_without_returns = get_partial_valid_orders_without_returns
    p 'partial valid_orders with out returns'
    sto_orders_without_returns.each do |order|
      p order
    end
    p '------------------------------------------------------------------------------'

    p 'barcodes with invalid characteristics'
    barcodes_in_fulfilment_location_and_in_other_location
    p '------------------------------------------------------------------------------'
  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

def valid_forward_shipment?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    return false if return_shipments.empty?

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

def barcodes_in_fulfilment_location_and_in_other_location
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    forward_shipment.shipment_lines.each do |shipment_line|
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      next unless barcode_locations

      next if barcode_locations.size > 1 && barcode_locations.none? { |bl| bl.quantity == 0 }

      if barcode_locations.size > 1
        barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
        p shipment_line.barcode if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
      end
    end
  end
end

def valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    # Check for return shipments for the current forward shipment
    return false unless get_valid_barcode_location(shipment_line)

    return false if ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
  end
  true
end

def partial_valid_shipment_without_returns?(forward_shipment)
  forward_shipment.shipment_lines.each do |shipment_line|
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations

    # Validate if the barcode has a valid quantity in any location
    valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
    return false unless valid_quantity_location
  end
  true
end

def get_partial_valid_barcodes(shipment_line)
  barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
  barcode_location = barcode_locations.find { |bl| bl.quantity == 1 }
  barcode_location if barcode_location
end

def write_orders_to_text_file(valid_orders, file_name)
  File.open(file_name, 'w') do |file|
    # Write a header line
    file.puts 'Fulfilment Location,Parent Order Code,Shipment ID,Barcode,SKU,Barcode Location,Quantity'

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

  write_orders_to_text_file(valid_orders, "#{@project_root}/results/valid_orders.csv")
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
  write_orders_to_text_file(partial_availability_orders, "#{@project_root}/results/partial_availability_orders.csv")
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

  write_orders_to_text_file(forwards_without_returns, "#{@project_root}/results/forwards_without_returns.csv")
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

  write_orders_to_text_file(partial_valid_orders, "#{@project_root}/results/partial_valid_orders_without_returns.csv")
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
  write_orders_to_text_file(all_forwards, "#{@project_root}/results/read_forwards.csv")
end

# Run the main method
main