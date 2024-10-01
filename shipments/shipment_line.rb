class ShipmentLine
  attr_accessor :sku, :barcode, :shipment_id

  def initialize(sku, barcode, shipment_id)
    @sku = sku
    @barcode = barcode
    @shipment_id = shipment_id
  end
end
