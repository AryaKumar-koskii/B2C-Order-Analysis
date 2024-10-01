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

    # Example queries:
    # Find a forward shipment by shipment ID
    forward_shipment = ForwardShipment.find_by_shipment_id('KO202061')
    if forward_shipment
      puts "Forward Shipment found: #{forward_shipment.forward_order_id}"
    else
      puts "Forward Shipment not found for KO202061"
    end

    # Find all forward shipments containing a specific barcode
    shipments_by_barcode = ForwardShipment.find_by_barcode('k948612')
    puts "Shipments with barcode 'k948612': #{shipments_by_barcode.inspect}"

    # Find all forward shipments without any return shipments
    shipments_without_returns = ForwardShipment.find_without_return_shipments
    puts "Forward shipments without returns: #{shipments_without_returns.inspect}"

    # Find all pending forward shipments
    pending_forward_shipments = ForwardShipment.all.select { |fs| fs.pending }
    puts "Pending Forward Shipments: #{pending_forward_shipments.inspect}"

  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

# Run the main method
main