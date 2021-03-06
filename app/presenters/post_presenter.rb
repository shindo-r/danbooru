class PostPresenter < Presenter
  def self.preview(post, options = {})
    if post.is_deleted? && !CurrentUser.is_privileged?
      return ""
    end
    
    flags = []
    flags << "pending" if post.is_pending?
    flags << "flagged" if post.is_flagged?
    flags << "deleted" if post.is_deleted?
    
    path = options[:path_prefix] || "/posts"
    
    html =  %{<article class="post-preview" id="post_#{post.id}" data-id="#{post.id}" data-tags="#{h(post.tag_string)}" data-uploader="#{h(post.uploader_name)}" data-rating="#{post.rating}" data-width="#{post.image_width}" data-height="#{post.image_height}" data-flags="#{flags.join(' ')}" data-parent-id="#{post.parent_id}" data-has-children="#{post.has_children?}">}
    html << %{<a href="#{path}/#{post.id}">}
    html << %{<img src="#{post.preview_file_url}" alt="#{h(post.tag_string)}">}
    html << %{</a>}
    html << %{</article>}
    html.html_safe
  end
  
  def initialize(post)
    @post = post
  end
  
  def preview_html
    PostPresenter.preview(@post)
  end
  
  def image_html(template)
    return template.content_tag("p", "This image was deleted.") if @post.is_deleted? && !CurrentUser.user.is_janitor?
    return template.content_tag("p", "You need a privileged account to see this image.") if !Danbooru.config.can_user_see_post?(CurrentUser.user, @post)
    
    if @post.is_flash?
      template.render("posts/partials/show/flash", :post => @post)
    elsif @post.is_image?
      template.render("posts/partials/show/image", :post => @post)
    end
  end
  
  def tag_list_html(template, options = {})
    @tag_set_presenter ||= TagSetPresenter.new(@post.tag_array)
    @tag_set_presenter.tag_list_html(template, options.merge(:show_extra_links => CurrentUser.user.is_privileged?))
  end
end
