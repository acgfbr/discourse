# A class we can use to serialize the site data
require_dependency 'score_calculator'
require_dependency 'trust_level'

class Site
  include ActiveModel::Serialization

  def initialize(guardian)
    @guardian = guardian
  end

  def site_setting
    SiteSetting
  end

  def notification_types
    Notification.types
  end

  def trust_levels
    TrustLevel.all
  end

  def user_fields
    UserField.all
  end

  def categories
    @categories ||= begin
      categories = Category
        .secured(@guardian)
        .joins('JOIN topics t on t.id = categories.topic_id')
        .select('categories.*, t.slug topic_slug')
        .order(:position)

      categories = categories.to_a

      with_children = Set.new
      categories.each do |c|
        if c.parent_category_id
          with_children << c.parent_category_id
        end
      end

      allowed_topic_create_ids =
        @guardian.anonymous? ? [] : Category.topic_create_allowed(@guardian).pluck(:id)
      allowed_topic_create = Set.new(allowed_topic_create_ids)

      by_id = {}

      category_user = {}
      unless @guardian.anonymous?
        category_user = Hash[*CategoryUser.where(user: @guardian.user).pluck(:category_id, :notification_level).flatten]
      end

      categories.each do |category|
        category.notification_level = category_user[category.id]
        category.permission = CategoryGroup.permission_types[:full] if allowed_topic_create.include?(category.id)
        category.has_children = with_children.include?(category.id)
        by_id[category.id] = category
      end

      categories.reject! { |c| c.parent_category_id && !by_id[c.parent_category_id] }
      categories
    end
  end

  def suppressed_from_homepage_category_ids
    categories.select { |c| c.suppress_from_homepage == true }.map(&:id)
  end

  def archetypes
    Archetype.list.reject { |t| t.id == Archetype.private_message }
  end

  def self.json_for(guardian)

    if guardian.anonymous? && SiteSetting.login_required
      return {
        periods: TopTopic.periods.map(&:to_s),
        filters: Discourse.filters.map(&:to_s),
        user_fields: UserField.all.map do |userfield|
          UserFieldSerializer.new(userfield, root: false, scope: guardian)
        end
      }.to_json
    end

    site = Site.new(guardian)
    MultiJson.dump(SiteSerializer.new(site, root: false, scope: guardian))
  end

end
