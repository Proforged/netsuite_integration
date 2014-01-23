require "sinatra"
require "endpoint_base"

require File.expand_path(File.dirname(__FILE__) + '/lib/netsuite_integration')

class NetsuiteEndpoint < EndpointBase::Sinatra::Base
  before do
    config = @config

    NetSuite.configure do
      reset!
      api_version  '2013_2'
      wsdl         'https://webservices.na1.netsuite.com/wsdl/v2013_2_0/netsuite.wsdl'
      sandbox      config.fetch('netsuite.sandbox', false)
      email        config.fetch('netsuite.email')
      password     config.fetch('netsuite.password')
      account      config.fetch('netsuite.account')
      role         config.fetch('netsuite.role_id', 3)
      read_timeout 100000000
      log          "#{`pwd`.chomp}/netsuite.log"
      log_level    :info
    end
  end

  post '/products' do
    begin
      products = NetsuiteIntegration::Product.new(@config)

      if products.collection.any?
        add_messages "product:import", products.messages
        add_parameter 'netsuite.last_updated_after', products.last_modified_date
        add_notification "info", "NetSuite Items imported as products up to #{products.last_modified_date}"
      else
        add_notification "info", "No product updated since #{@config.fetch('netsuite.last_updated_after')}"
      end

      process_result 200
    rescue Exception => e
      add_notification "error", e.message, nil, { backtrace: e.backtrace.to_a.join("\n\t") }
      process_result 500
    end
  end

  post '/orders' do
    begin
      order = NetsuiteIntegration::Order.new(@config, @message)

      unless order.imported?
        if order.import
          add_notification "info", "Order #{order.sales_order.external_id} imported into NetSuite (internal id #{order.sales_order.internal_id})"
          process_result 200
        else
          add_notification "error", "Failed to import order #{order.sales_order.external_id} into Netsuite"
          process_result 500
        end
      else
        if order.got_paid?
          if order.create_customer_deposit
            add_notification "info", "Customer Deposit created for NetSuite Sales Order #{order.sales_order.external_id}"
            process_result 200
          else
            add_notification "error", "Failed to create a Customer Deposit for NetSuite Sales Order #{order.sales_order.external_id}"
            process_result 500
          end
        else
          process_result 200
        end
      end
    rescue Exception => e
      add_notification "error", e.message, nil, { backtrace: e.backtrace.to_a.join("\n\t") }
      process_result 500
    end
  end

  post '/cancel_order' do
    begin
      refund = NetsuiteIntegration::Refund.new(@config, @message)

      if refund.process!
        add_notification "info", "Customer Refund created for NetSuite Sales Order #{@message[:payload][:order][:number]}"
        process_result 200
      else
        add_notification "error", "Failed to create a Customer Refund for NetSuite Sales Order #{@message[:payload][:order][:number]}"
        process_result 500
      end
    rescue Exception => e
      add_notification "error", e.message, nil, { backtrace: e.backtrace.to_a.join("\n\t") }
      process_result 500
    end
  end

  post '/inventory_stock' do
    begin
      stock = NetsuiteIntegration::InventoryStock.new(@config, @message)
      add_message 'stock:actual', { sku: stock.sku, quantity: stock.quantity_available }
      add_notification "info", "#{stock.quantity_available} units available of #{stock.sku} according to NetSuite"
    rescue NetSuite::RecordNotFound
      add_notification "info", "Inventory Item #{@message[:payload][:sku]} not found on NetSuite"
    end

    process_result 200
  end

  post '/shipments' do
  end
end
