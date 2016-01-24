require 'sequel'

class OutstandingCoin < Sequel::Model
  OutstandingCoin.plugin :timestamps, :force=>true, :update_on_create=> true, :create=>:createdAt, :update=>:updatedAt
end
