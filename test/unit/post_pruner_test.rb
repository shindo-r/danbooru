require 'test_helper'

class PostPrunerTest < ActiveSupport::TestCase
  setup do
    @user = FactoryGirl.create(:admin_user)
    CurrentUser.user = @user
    CurrentUser.ip_addr = "127.0.0.1"
    MEMCACHE.flush_all
    
    @flagger = FactoryGirl.create(:user)
    @old_post = FactoryGirl.create(:post, :created_at => 5.days.ago, :is_pending => true)
    @unresolved_flagged_post = FactoryGirl.create(:post, :is_flagged => true)
    @resolved_flagged_post = FactoryGirl.create(:post, :is_flagged => true)

    CurrentUser.scoped(@flagger, "127.0.0.2") do
      @unresolved_post_flag = FactoryGirl.create(:post_flag, :created_at => 5.days.ago, :is_resolved => false, :post_id => @unresolved_flagged_post.id)
      @resolved_post_flag = FactoryGirl.create(:post_flag, :created_at => 5.days.ago, :is_resolved => true, :post_id => @resolved_flagged_post.id)
    end
    
    PostPruner.new.prune!
  end
  
  teardown do
    CurrentUser.user = nil
    CurrentUser.ip_addr = nil
  end
  
  should "prune old pending posts" do
    @old_post.reload
    assert(@old_post.is_deleted?)
  end
  
  should "prune old flagged posts that are still unresolved" do
    @unresolved_flagged_post.reload
    assert(@unresolved_flagged_post.is_deleted?)
  end
  
  should "not prune old flagged posts that are resolved" do
    @resolved_flagged_post.reload
    assert(!@resolved_flagged_post.is_deleted?)
  end
end
