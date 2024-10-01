require 'csv'
require_relative 'shipment_line'

class ForwardShipment
  attr_accessor :location, :forward_order_id, :parent_order_id, :shipment_lines, :return_shipments, :pending

  # Static data structures for quick lookup
  @@forward_shipments_by_id = {}
  @@forward_shipments_by_barcode = Hash.new { |hash, key| hash[key] = [] }
  @@forward_shipments_by_sku = Hash.new { |hash, key| hash[key] = [] }
  @@forward_shipments_without_returns = []
  @@forward_shipments_by_shipment_id = {}

  def initialize(location, forward_order_id, parent_order_id, pending=false)
    @location = location
    @forward_order_id = forward_order_id
    @parent_order_id = parent_order_id
    @shipment_lines = []   # Array of ShipmentLine objects
    @return_shipments = [] # Array of associated ReturnShipments
    @pending = pending

    # Populate static data structures
    @@forward_shipments_by_id[@parent_order_id] = self
    @@forward_shipments_by_shipment_id[@forward_order_id] = self
    @@forward_shipments_without_returns << self unless @return_shipments.any?
  end

  # Method to add a shipment line (SKU and barcode)
  def add_shipment_line(sku, barcode)
    if @shipment_lines.any? { |line| line.barcode == barcode }
      raise "Duplicate barcode '#{barcode}' in forward shipment '#{@forward_order_id}'."
    end
    shipment_line = ShipmentLine.new(sku, barcode)
    @shipment_lines << shipment_line

    # Indexing for queries
    @@forward_shipments_by_barcode[barcode] << self
    @@forward_shipments_by_sku[sku] << self
  end

  # Class method to read from a CSV file, considering only pending orders
  def self.read_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      forward_order_id = row['Channel Order ID']

      # Only process if the forward order is pending
      next unless PendingForward.pending?(forward_order_id)

      location_name = row['Fulfilment Location Name']
      location = Location.find_by_full_name(location_name)
      raise "Location not found for fulfillment location name: '#{location_name}'" unless location

      # Create a new forward shipment
      forward_shipment = ForwardShipment.new(
        location,
        forward_order_id,
        row['Parent Order ID'],
        true
      )

      # Add shipment line
      forward_shipment.add_shipment_line(row['Client SKU ID / EAN'], row['External Item Code'])
    end
  end

  # Query methods for the required data
  def self.find_by_shipment_id(shipment_id)
    @@forward_shipments_by_shipment_id[shipment_id]
  end

  def self.find_by_barcode(barcode)
    @@forward_shipments_by_barcode[barcode]
  end

  def self.find_by_sku(sku)
    @@forward_shipments_by_sku[sku]
  end

  def self.find_without_return_shipments
    @@forward_shipments_without_returns
  end

  def self.find_by_parent_id(parent_id)
    @@forward_shipments_by_id[parent_id]
  end

  def self.all
    @@forward_shipments_by_id.values
  end

  def add_return_shipment(return_shipment)
    @return_shipments << return_shipment
    @@forward_shipments_without_returns.delete(self)
  end
end