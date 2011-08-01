require "test_helper"

module Moderator
  class IpAddrSearchTest < ActiveSupport::TestCase
    context "an ip addr search" do
      setup do
        @user = Factory.create(:user)
        CurrentUser.user = @user
        CurrentUser.ip_addr = "127.0.0.1"
        Factory.create(:comment)
        MEMCACHE.flush_all
      end
  
      teardown do
        CurrentUser.user = nil
        CurrentUser.ip_addr = nil
      end
    
      should "find by ip addr" do
        @search = IpAddrSearch.new(:ip_addr => "127.0.0.1")
        assert_equal({@user.id.to_s => 2}, @search.execute)
      end
      
      should "find by user id" do
        @search = IpAddrSearch.new(:user_id => @user.id.to_s)
        assert_equal({"127.0.0.1" => 2}, @search.execute)
      end

      should "find by user name" do
        @search = IpAddrSearch.new(:user_name => @user.name)
        assert_equal({"127.0.0.1" => 2}, @search.execute)
      end
    end
  end
end