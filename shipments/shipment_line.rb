class ShipmentLine
  attr_accessor :sku, :barcode

  def initialize(sku, barcode)
    @sku = sku
    @barcode = barcode
  end
end
