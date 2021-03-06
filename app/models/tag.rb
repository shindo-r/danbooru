class Tag < ActiveRecord::Base
  attr_accessible :category
  after_save :update_category_cache
  has_one :wiki_page, :foreign_key => "name", :primary_key => "title"
  scope :name_matches, lambda {|name| where("name LIKE ? ESCAPE E'\\\\'", name.downcase.to_escaped_for_sql_like)}
  scope :named, lambda {|name| where("name = ?", TagAlias.to_aliased([name]).join(""))}
  search_methods :name_matches

  class CategoryMapping
    Danbooru.config.reverse_tag_category_mapping.each do |value, category|
      define_method(category.downcase) do
        value
      end
    end
    
    def regexp
      @regexp ||= Regexp.compile(Danbooru.config.tag_category_mapping.keys.sort_by {|x| -x.size}.join("|"))
    end
    
    def value_for(string)
      Danbooru.config.tag_category_mapping[string.downcase] || 0
    end
  end
  
  module CountMethods
    def counts_for(tag_names)
      select_all_sql("SELECT name, post_count FROM tags WHERE name IN (?)", tag_names)
    end
  end
  
  module ViewCountMethods
    def increment_view_count(name)
      Cache.incr("tvc:#{Cache.sanitize(name)}")
    end
  end
  
  module CategoryMethods
    module ClassMethods
      def categories
        @category_mapping ||= CategoryMapping.new
      end
      
      def select_category_for(tag_name)
        select_value_sql("SELECT category FROM tags WHERE name = ?", tag_name).to_i
      end
      
      def category_for(tag_name)
        Cache.get("tc:#{Cache.sanitize(tag_name)}") do
          select_category_for(tag_name)
        end
      end
      
      def categories_for(tag_names)
        Cache.get_multi(tag_names, "tc") do |name|
          select_category_for(name)
        end
      end
    end
    
    def self.included(m)
      m.extend(ClassMethods)
    end

    def category_name
      Danbooru.config.reverse_tag_category_mapping[category]
    end
    
    def update_category_cache
      Cache.put("tc:#{Cache.sanitize(name)}", category, 1.hour)
    end
  end
  
  module StatisticsMethods
    def trending
      raise NotImplementedError
    end
  end
  
  module NameMethods
    module ClassMethods
      def normalize_name(name)
        name.downcase.tr(" ", "_").gsub(/\A[-~]+/, "").gsub(/\*/, "")
      end

      def find_or_create_by_name(name, options = {})
        name = normalize_name(name)
        category = categories.general

        if name =~ /\A(#{categories.regexp}):(.+)\Z/
          category = categories.value_for($1)
          name = $2
        end

        tag = find_by_name(name)

        if tag
          if category > 0
            tag.update_column(:category, category)
            tag.update_category_cache
          end

          tag
        else
          Tag.new.tap do |t|
            t.name = name
            t.category = category
            t.save
          end
        end
      end
    end
    
    def self.included(m)
      m.extend(ClassMethods)
    end
  end

  module ParseMethods
    def normalize(query)
      query.to_s.downcase.strip
    end
    
    def scan_query(query)
      normalize(query).scan(/\S+/).uniq
    end

    def scan_tags(tags)
      normalize(tags).gsub(/[%,]/, "").scan(/\S+/).uniq
    end

    def parse_cast(object, type)
      case type
      when :integer
        object.to_i

      when :float
        object.to_f

      when :date
        begin
          object.to_date
        rescue Exception
          nil
        end

      when :filesize
        object =~ /\A(\d+(?:\.\d*)?|\d*\.\d+)([kKmM]?)[bB]?\Z/

      	size = $1.to_f
      	unit = $2

      	conversion_factor = case unit
    	  when /m/i
    	    1024 * 1024
    	  when /k/i
    	    1024
    	  else
    	    1
  	    end

  	    (size * conversion_factor).to_i
      end
    end

    def parse_helper(range, type = :integer)
      # "1", "0.5", "5.", ".5":
      # (-?(\d+(\.\d*)?|\d*\.\d+))
      case range
      when /\A(.+?)\.\.(.+)/
        return [:between, parse_cast($1, type), parse_cast($2, type)]

      when /\A<=(.+)/, /\A\.\.(.+)/
        return [:lte, parse_cast($1, type)]

      when /\A<(.+)/
        return [:lt, parse_cast($1, type)]

      when /\A>=(.+)/, /\A(.+)\.\.\Z/
        return [:gte, parse_cast($1, type)]

      when /\A>(.+)/
        return [:gt, parse_cast($1, type)]

      else
        return [:eq, parse_cast(range, type)]

      end
    end
    
    def parse_tag(tag, output)
      if tag[0] == "-" && tag.size > 1
        output[:exclude] << tag[1..-1]
        
      elsif tag[0] == "~" && tag.size > 1
        output[:include] << tag[1..-1]
        
      elsif tag =~ /\*/
        matches = Tag.name_matches(tag).all(:select => "name", :limit => Danbooru.config.tag_query_limit, :order => "post_count DESC").map(&:name)
        matches = ["~no_matches~"] if matches.empty?
        output[:include] += matches
        
      else
        output[:related] << tag
      end
    end

    def parse_query(query, options = {})
      q = {}
      q[:tags] = {
        :related => [],
        :include => [],
        :exclude => []
      }
      
      scan_query(query).each do |token|
        if token =~ /\A(-uploader|uploader|-approver|approver|-pool|pool|-fav|fav|sub|md5|-rating|rating|width|height|mpixels|score|filesize|source|id|date|order|status|tagcount|gentags|arttags|chartags|copytags|parent):(.+)\Z/
          case $1
          when "-uploader"
            q[:uploader_id_neg] ||= []
            q[:uploader_id_neg] << User.name_to_id($2)
            
          when "uploader"
            q[:uploader_id] = User.name_to_id($2)
            
          when "-approver"
            q[:approver_id_neg] ||= []
            q[:approver_id_neg] << User.name_to_id($2)
            
          when "approver"
            q[:approver_id] = User.name_to_id($2)
            
          when "-pool"
            q[:tags][:exclude] << "pool:#{Pool.name_to_id($2)}"
            
          when "pool"
            q[:tags][:related] << "pool:#{Pool.name_to_id($2)}"
          
          when "-fav"
            q[:tags][:exclude] << "fav:#{User.name_to_id($2)}"

          when "fav"
            q[:tags][:related] << "fav:#{User.name_to_id($2)}"

          when "sub"
            q[:subscriptions] ||= []
            q[:subscriptions] << $2

          when "md5"
            q[:md5] = $2.split(/,/)

          when "-rating"
            q[:rating_negated] = $2

          when "rating"
            q[:rating] = $2
            
          when "id"
            q[:post_id] = parse_helper($2)
            
          when "width"
            q[:width] = parse_helper($2)
            
          when "height"
            q[:height] = parse_helper($2)
            
          when "mpixels"
            q[:mpixels] = parse_helper($2, :float)

          when "score"
            q[:score] = parse_helper($2)

          when "filesize"
      	    q[:filesize] = parse_helper($2, :filesize)

          when "source"
            q[:source] = $2.to_escaped_for_sql_like + "%"

          when "date"
            q[:date] = parse_helper($2, :date)

          when "tagcount"
            q[:tag_count] = parse_helper($2)
            
          when "gentags"
            q[:general_tag_count] = parse_helper($2)

          when "arttags"
            q[:artist_tag_count] = parse_helper($2)

          when "chartags"
            q[:character_tag_count] = parse_helper($2)

          when "copytags"
            q[:copyright_tag_count] = parse_helper($2)
            
          when "parent"
            q[:parent_id] = $2.to_i
            
          when "order"
            q[:order] = $2

          when "status"
            q[:status] = $2
            
          end
          
        else
          parse_tag(token, q[:tags])
        end
      end
      
      normalize_tags_in_query(q)

      return q
    end

    def normalize_tags_in_query(query_hash)
      query_hash[:tags][:exclude] = TagAlias.to_aliased(query_hash[:tags][:exclude])
      query_hash[:tags][:include] = TagAlias.to_aliased(query_hash[:tags][:include])
      query_hash[:tags][:related] = TagAlias.to_aliased(query_hash[:tags][:related])
    end
  end
  
  module RelationMethods
    def update_related
      return unless should_update_related?
      self.related_tags = RelatedTagCalculator.calculate_from_sample_to_array(name).join(" ")
      self.related_tags_updated_at = Time.now
      save
    end
    
    def update_related_if_outdated
      delay.update_related if should_update_related?
    end
    
    def related_cache_expiry
      base = Math.sqrt([post_count, 0].max)
      if base > 24
        24
      else
        base
      end
    end
    
    def should_update_related?
      related_tags.blank? || related_tags_updated_at.blank? || related_tags_updated_at < related_cache_expiry.hours.ago
    end
    
    def related_tag_array
      update_related_if_outdated
      related_tags.to_s.split(/ /).in_groups_of(2)
    end
  end
  
  module SuggestionMethods
    def find_suggestions(query)
      query_tokens = query.split(/_/)
      
      if query_tokens.size == 2
        search_for = query_tokens.reverse.join("_").to_escaped_for_sql_like
      else
        search_for = "%" + query.to_escaped_for_sql_like + "%"
      end

      Tag.where(["name LIKE ? ESCAPE E'\\\\' AND post_count > 0 AND name <> ?", search_for, query]).all(:order => "post_count DESC", :limit => 6, :select => "name").map(&:name).sort
    end
  end
  
  extend CountMethods
  extend ViewCountMethods
  include CategoryMethods
  extend StatisticsMethods
  include NameMethods
  extend ParseMethods
  include RelationMethods
  extend SuggestionMethods
end
