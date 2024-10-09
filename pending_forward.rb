require 'csv'
require 'set'

class PendingForward
  @pending_order_ids = Set.new

  # Class method to load pending forwards from CSV
  def self.load_from_csv(file_path)
    require 'set'
    CSV.foreach(file_path, headers: true) do |row|
      if row['is_completed'] != "TRUE"
        forward_order_code = row['forward_order_code']
        @pending_order_ids.add(forward_order_code)
      end
    end
  end

  # Method to check if a forward order is pending
  def self.pending?(forward_order_id)
    @pending_order_ids.include?(forward_order_id)
  end
end