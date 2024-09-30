require 'csv'

class ForwardShipment
  attr_accessor :location, :forward_order_id, :parent_order_id, :shipment_lines, :return_shipments

  # Static data structures for quick lookup
  @forward_shipments_by_id = {}
  @forward_shipments_by_barcode = Hash.new { |hash, key| hash[key] = [] }
  @forward_shipments_by_sku = Hash.new { |hash, key| hash[key] = [] }
  @forward_shipments_without_returns = []

  def initialize(location, forward_order_id, parent_order_id)
    @location = location
    @forward_order_id = forward_order_id
    @parent_order_id = parent_order_id
    @shipment_lines = []   # Array of ShipmentLine objects
    @return_shipments = [] # Array of associated ReturnShipments

    @forward_shipments_by_id[@forward_order_id] = self
    @forward_shipments_without_returns << self
  end

  # Method to add a shipment line (SKU and barcode)
  def add_shipment_line(sku, barcode)
    shipment_line = ShipmentLine.new(sku, barcode)
    @shipment_lines << shipment_line

    # Indexing for queries
    @forward_shipments_by_barcode[barcode] << self
    @forward_shipments_by_sku[sku] << self
  end

  # Class method to read from a CSV file
  def self.read_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      location = Location.find_by_full_name(row['Fulfillment Location Name'])
      raise "Location not found for fulfillment location name: '#{row['Fulfillment Location Name']}'" unless location

      # Create a new forward shipment
      forward_shipment = ForwardShipment.new(
        location,
        row['Channel Order ID'],
        row['Parent Order ID']
      )

      # Add shipment line
      forward_shipment.add_shipment_line(row['Client SKU ID / EAN'], row['External Item Code'])
    end
  end

  # Query methods for the required data
  def self.find_by_shipment_id(shipment_id)
    @forward_shipments_by_id[shipment_id]
  end

  def self.find_by_barcode(barcode)
    @forward_shipments_by_barcode[barcode]
  end

  def self.find_by_sku(sku)
    @forward_shipments_by_sku[sku]
  end

  def self.find_without_return_shipments
    @forward_shipments_without_returns
  end

  def add_return_shipment(return_shipment)
    @return_shipments << return_shipment
    @forward_shipments_without_returns.delete(self)
  end
end