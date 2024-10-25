# frozen_string_literal: true
require 'csv'

class ReadSTOFile
  attr_accessor :from_loc, :to_loc, :quantity, :sku, :barcode

  @sto_records_by_from_to = Hash.new { |h, k| h[k] = [] }

  class << self
    attr_accessor :sto_records_by_from_to

    # CSV headers: Fulfilment Location, Parent Order Code, Shipment ID, Barcode, SKU, Barcode Location, Quantity
    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        ReadSTOFile.new(
          from_loc: row['Barcode Location'],
          to_loc: row['Fulfilment Location'],
          barcode: row['Barcode'],
          quantity: row['Quantity'],
          sku: row['SKU']
        )
      end
    end

    def find_by_from_to(from_loc, to_loc)
      sto_records_by_from_to[[from_loc, to_loc]]
    end
  end

  def initialize(from_loc:, to_loc:, barcode:, quantity:, sku:)
    @from_loc = from_loc
    @to_loc = to_loc
    @barcode = barcode
    @quantity = quantity.to_i
    @sku = sku

    key = [from_loc, to_loc]
    self.class.sto_records_by_from_to[key] << self
  end
end