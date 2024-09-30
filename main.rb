require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'location'
require_relative 'barcode_location'

def main
  begin
    # Step 1: Load the location alias mapping
    puts "Loading location alias mapping..."
    Location.load_locations('location_alias_mapping.csv')

    # Step 2: Load forward shipments
    puts "Loading forward shipments..."
    ForwardShipment.read_from_csv('Forwards.csv')

    # Step 3: Load return shipments
    puts "Loading return shipments..."
    ReturnShipment.read_from_csv('ReturnOrderItemLevelReport.csv')

    # Step 4: Load barcode location data
    puts "Loading barcode location data..."
    BarcodeLocation.read_from_csv('barcode_location.csv')

    puts "Data loading completed successfully!"

    # Optionally: Perform any operations on the data
    # Example: Print a forward shipment
    forward_shipment = ForwardShipment.find_without_return_shipments
    if forward_shipment
      puts "Forward Shipment found: #{forward_shipment.forward_order_id}"
    else
      puts "Forward Shipment not found for KO202061"
    end

  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

# Run the main method
main