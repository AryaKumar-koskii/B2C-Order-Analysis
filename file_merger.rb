require 'csv'
require 'fileutils'
require_relative 'parent_order_mapping'
class FileMerger
  attr_reader :project_root

  def initialize(project_root)
    @project_root = project_root
  end

  def merge_shipped_order
    input_directory = File.join(project_root, 'csv_files', 'WMS_outward')
    output_file = File.join(project_root, 'csv_files/new_merged', 'WMS_outward.csv')

    required_columns = ['Pack Type', 'Order Type']
    filter_conditions = ->(row) { row['Pack Type'] == 'B2C' && row['Order Type'] == 'SALES' }

    process_csv_files(input_directory, output_file, required_columns, filter_conditions)
  end

  def merge_sfs_order
    input_directory = File.join(project_root, 'csv_files', 'SFS_outward')
    output_file = File.join(project_root, 'csv_files/new_merged', 'SFS_outward.csv')

    required_columns = ['Channel ID', 'SFS/USP Order Status']
    filter_conditions = ->(row) { row['Channel ID'] != 'SHOPIFYUS' && ['PACKED', 'COMPLETED', 'PICKING_COMPLETED'].include?(row['SFS/USP Order Status']) }

    process_csv_files(input_directory, output_file, required_columns, filter_conditions)
  end

  def merge_return_order_files
    input_directory = File.join(project_root, 'csv_files', 'return_order')
    output_file = File.join(project_root, 'csv_files/new_merged', 'return_order.csv')

    # Filter rows where 'Return Order Status' is 'COMPLETED' and 'Return Order Item Status' is 'RECEIVED'
    process_csv_files(input_directory, output_file, [], ->(row) {
      row['Return Order Status'] == 'COMPLETED' && row['Return Order Item Status'] == 'RECEIVED'
    })
  end

  def merge_order_files
    merge_shipped_order
    merge_sfs_order

    parent_order_mapping = ParentOrderMapping.new('../csv_files/support_data/forward_Parent_order_code_mapping.csv')
    file1_path = File.join(project_root, 'csv_files/new_merged/SFS_outward.csv')
    file2_path = File.join(project_root, 'csv_files/new_merged/WMS_outward.csv')
    output_file = File.join(project_root, 'csv_files/new_merged/forward_order.csv')

    begin
      df1 = CSV.read(file1_path, headers: true).map(&:to_hash)
      df2 = CSV.read(file2_path, headers: true).map(&:to_hash)
    rescue StandardError => e
      puts "Error reading files: #{e.message}"
      return
    end

    df1.each do |row|
      row['Fulfilment Location Name'] = row.delete('fulfillment_location_name') if row.key?('fulfillment_location_name')
      row['External Item Code'] = row.delete('External Item ID') if row.key?('External Item ID')
      row['Sales Channel'] = row.delete('Channel ID') if row.key?('Channel ID')
      row['Client SKU ID / EAN'] = row.delete('Client SKU ID') if row.key?('Client SKU ID')
      row['Parent Order ID'] = nil
    end

    columns_to_keep = [
      'Fulfilment Location Name', 'Channel Order ID', 'Parent Order ID', 'Shipment ID',
      'External Item Code', 'Client SKU ID / EAN', 'Sales Channel'
    ]

    merged_df = (df1 + df2).map { |row| row.slice(*columns_to_keep) }.uniq
    merged_df.reject! { |row| row['Channel Order ID'].nil? || row['Shipment ID'].nil? }

    merged_df.each do |row|
      if row['Parent Order ID'].nil? || row['Parent Order ID'].empty?
        row['Parent Order ID'] = parent_order_mapping.get_parent_order_code_using_order_code(row['Channel Order ID'])
      end
    end

    CSV.open(output_file, 'w', write_headers: true, headers: columns_to_keep) do |csv|
      merged_df.each { |row| csv << row.values }
    end

    puts "\nMerged data has been saved to '#{output_file}'"
  end

  private

  def process_csv_files(input_directory, output_file, required_columns, filter_conditions)
    return [] unless Dir.exist?(input_directory)

    csv_files = Dir.glob(File.join(input_directory, '*.csv'))
    return [] if csv_files.empty?

    filtered_rows = []

    csv_files.each do |file|
      begin
        csv_data = CSV.read(file, headers: true)
      rescue StandardError => e
        puts "Error reading #{file}: #{e.message}"
        next
      end

      unless (required_columns - csv_data.headers).empty?
        puts "Skipping #{file}: Missing required columns #{required_columns}"
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
    end

    filtered_rows.size
  end
end