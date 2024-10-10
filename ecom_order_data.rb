# frozen_string_literal: true
require 'csv'
require_relative 'pending_forward'

class EcomOrderData
  attr_accessor :id, :payload, :event_name, :parent_order_code, :status

  @ecom_data_by_parent_order_code_and_event_name = {}
  @ecom_data_by_event_name = Hash.new { |h,k| h[k] = [] }
  class << self
    attr_accessor :ecom_data_by_parent_order_code_and_event_name, :return_payloads

    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        id = row['id']
        payload = row['ecom_order_json']
        event_name = row['event_name']
        parent_order_code = row['order_number']

        next unless PendingForward.pending?(parent_order_code)

        unless %w[order_fulfilment order_cancellation].include?(event_name)
          next
        end

        EcomOrderData.new(id, payload, event_name, parent_order_code)
      end

      def find_by_parent_order_coder_and_event_name(parent_order_code, event_name)
        key = [parent_order_code, event_name]
        @ecom_data_by_parent_order_code_and_event_name[key]
      end

      def find_return_by_parent_order_code(parent_order_code)
        @return_payloads[parent_order_code]
      end
    end
  end
    def initialize(id, payload, event_name, parent_order_code)
      @id = id
      @payload = payload
      @event_name = event_name
      @parent_order_code = parent_order_code

      if event_name == 'order_cancellation'
        self.class.return_payloads[parent_order_code] << self
      else
        key = [parent_order_code, event_name]
        self.class.ecom_data_by_parent_order_code_and_event_name[key] = self
      end

    end
  end
