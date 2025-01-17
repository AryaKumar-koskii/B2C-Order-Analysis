require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'order_shipment_data'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'
require_relative 'file_merger'
require_relative 'write_filtered_data'
require_relative 'valid_order_filters'
require_relative 'Const'
require_relative 'shipments/fetch_completed_shipments'
require 'csv'
require 'fileutils'
require 'set'

def load_files

  puts 'Loading location alias mapping...'
  Location.load_locations("#{@project_root}/csv_files/support_data/location_alias_mapping.csv")

  puts 'Loading pending forwards...'
  PendingForward.load_from_csv("#{@project_root}/csv_files/support_data/pending_forwards.csv")

  puts 'Loading forward shipments...'
  ForwardShipment.read_from_csv("#{@project_root}/csv_files/new_merged/forward_order.csv")

  p 'Loading completed shipments data...'
  OrderShipmentData.read_from_csv("#{@project_root}/csv_files/support_data/completed_shipments.csv")

  puts 'Loading return shipments...'
  ReturnShipment.read_from_csv("#{@project_root}/csv_files/new_merged/return_order.csv")

  puts 'Loading barcode location data...'
  BarcodeLocation.read_from_csv("#{@project_root}/csv_files/support_data/barcode_location.csv")

  puts 'Data loading completed successfully!'
end

def main
  @project_root =Const::PROJECT_ROOT
  @result_direct = Const::RESULT_DIRECT

  fetch_completed_shipments = false
  needs_merge = false
  need_forward_reports_to_retry = true
  need_invalid_order_data = false

  begin
    file_merger.merge_return_order_files if needs_merge
    file_merger.merge_order_files if needs_merge

    FetchCompletedShipments.fetch_completed_shipments if fetch_completed_shipments

    load_files

    # pending_returns

    pending_forwards
    if need_forward_reports_to_retry
      process_valid_orders_with_returns
      process_orders_with_wrong_barcode_location_with_returns
      process_valid_orders_without_returns
      process_partial_valid_orders_without_returns
      process_valid_orders_with_returns_at_shipment_level
      process_orders_with_wrong_barcode_location_with_returns_at_shipment_level
      process_valid_orders_without_returns_at_shipment_level
      process_partial_valid_orders_without_returns_at_shipment_level
    end

    if need_invalid_order_data
      WriteFilteredData.run_methods
    end

    puts 'Processing completed successfully!'
  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

def pending_forwards
  puts 'all pending barcodes needs to be posted'
  get_all_pending_barcodes
  p "written into #{@result_direct}/pending_deliveries_at_barcode_level.csv"
end

def process_valid_orders_with_returns
  puts 'Processing valid orders with returns...'
  valid_orders = WriteFilteredData.get_valid_forward_orders_with_returns
  valid_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_orders_with_wrong_barcode_location_with_returns
  puts 'Processing orders with barcode in different location with returns...'
  sto_orders = WriteFilteredData.get_orders_with_wrong_barcode_location_with_returns
  sto_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_valid_orders_without_returns
  puts 'Processing valid orders without returns...'
  valid_orders_without_returns = WriteFilteredData.get_orders_without_returns_at_right_location
  valid_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_partial_valid_orders_without_returns
  puts 'Processing partial valid orders without returns...'
  sto_orders_without_returns = WriteFilteredData.get_partial_valid_orders_without_returns
  sto_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_valid_orders_with_returns_at_shipment_level
  puts 'Processing valid orders with returns at shipment level...'
  valid_orders = WriteFilteredData.get_valid_forward_orders_with_returns(true)
  valid_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_orders_with_wrong_barcode_location_with_returns_at_shipment_level
  puts 'Processing orders with barcode in different location with returns at shipment level...'
  sto_orders = WriteFilteredData.get_orders_with_wrong_barcode_location_with_returns(true)
  sto_orders.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_valid_orders_without_returns_at_shipment_level
  puts 'Processing valid orders without returns at shipment level...'
  valid_orders_without_returns = WriteFilteredData.get_orders_without_returns_at_right_location(true)
  valid_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def process_partial_valid_orders_without_returns_at_shipment_level
  puts 'Processing partial valid orders without returns at shipment level...'
  sto_orders_without_returns = WriteFilteredData.get_partial_valid_orders_without_returns(true)
  sto_orders_without_returns.each { |order| puts order }
  puts '------------------------------------------------------------------------------'
end

def get_all_pending_barcodes
  shipment_barcodes = []
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    forward_shipment.shipment_lines.each do |shipment_line|
      shipments = OrderShipmentData.shipment_data_by_parent_order_code[forward_shipment.parent_order_id]
      unless shipments.include? shipment_line.shipment_id
        # return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
        # next unless return_shipments.empty?
        barcode_location = BarcodeLocation.find_by_barcode(shipment_line.barcode)
        shipment_barcodes << {
          fulfilment_location: shipment_line.fulfilment_location,
          parent_order_code: forward_shipment.parent_order_id,
          shipment_id: shipment_line.shipment_id,
          sku: shipment_line.sku,
          barcode: shipment_line.barcode,
          barcode_location: if barcode_location
                              if barcode_location.size > 1
                                "barcode in multiple location"
                              else
                                barcode_location.first.location
                              end
                            else
                              nil
                            end,
          quantity: barcode_location ? barcode_location[0].quantity : nil,
        }
      end
    end
  end

  file_name = "#{@result_direct}pending_deliveries_at_barcode_level.csv"
  WriteFilteredData.write_orders_to_text_file(shipment_barcodes, file_name)
end

def pending_returns
  returns = []
  ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
    return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
    # p return_shipments unless return_shipments.empty?
    if return_shipments.empty?
      next
    end

    return_shipments.each do |return_shipment|
      returns << return_shipment
    end
  end
  file_name = "#{@result_direct}pending_return_orders.csv"
  WriteFilteredData.write_orders_to_text_file(returns, file_name, true)
end

main
