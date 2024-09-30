require 'csv'

class ReturnShipment
  attr_accessor :forward_shipment, :location, :return_order_status, :shipment_lines

  # Static data structure for looking up return shipments by forward shipment
  @return_shipments_by_forward_shipment = Hash.new { |hash, key| hash[key] = [] }

  def initialize(forward_shipment, location, return_order_status)
    @forward_shipment = forward_shipment
    @location = location
    @return_order_status = return_order_status
    @shipment_lines = [] # Array of ShipmentLine objects

    forward_shipment.add_return_shipment(self)
    @return_shipments_by_forward_shipment[forward_shipment] << self
  end

  # Method to add a shipment line (SKU and barcode)
  def add_shipment_line(sku, barcode)
    @shipment_lines << ShipmentLine.new(sku, barcode)
  end

  # Class method to read from a CSV file
  def self.read_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      location = Location.find_by_full_name(row['Fulfillment Location Name'])
      raise "Location not found for fulfillment location name: '#{row['Fulfillment Location Name']}'" unless location

      # Find the corresponding forward shipment by order ID
      forward_shipment = ForwardShipment.find_by_shipment_id(row['Channel Parent Order ID'])
      raise "Forward shipment not found for Parent Order ID: '#{row['Channel Parent Order ID']}'" unless forward_shipment

      # Check if the SKU and barcode match any line in the forward shipment
      matching_shipment_line = forward_shipment.shipment_lines.find do |line|
        (line.sku == row['Client SKU ID / EAN'] || row['External Item Code'] && line.barcode == row['External Item Code'])
      end

      raise "No matching forward shipment line found for SKU #{row['Client SKU ID / EAN']} or barcode #{row['External Item Code']}" unless matching_shipment_line

      # Create return shipment
      return_shipment = ReturnShipment.new(
        forward_shipment,
        location,
        row['Return Order Status']
      )

      # Add shipment line
      return_shipment.add_shipment_line(row['Client SKU ID / EAN'], row['External Item Code'])
    end
  end

  # Return shipments associated with a forward shipment
  def self.find_by_forward_shipment(forward_shipment)
    @return_shipments_by_forward_shipment[forward_shipment]
  end
end