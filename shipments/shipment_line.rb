class ShipmentLine
  attr_accessor :fulfilment_location, :sku, :barcode, :shipment_id

  def initialize(fulfilment_location = nil, sku, barcode, shipment_id)
    @fulfilment_location = fulfilment_location
    @sku = sku
    @barcode = barcode&.to_s&.upcase&.strip
    @shipment_id = shipment_id
  end
end
