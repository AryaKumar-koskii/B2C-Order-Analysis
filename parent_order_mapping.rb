# frozen_string_literal: true
require 'csv'
class ParentOrderMapping
  def initialize(file_path)
    @file_path = file_path
    @mapping = load_mappings
  end

  def load_mappings
    mappings={}
    CSV.foreach(@file_path, headers: true) do |row|
      order_code = row['order code']
      parent_order_code = row['parent_order_code']
      mappings[order_code] = parent_order_code
    end
    mappings
  end

  def get_parent_order_code_using_order_code(order_code)
    @mapping[order_code]
  end
end

