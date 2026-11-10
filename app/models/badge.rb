# frozen_string_literal: true

class Badge < ActiveRecord::Base
  include GlobalPath
  include HasSanitizableFields

  # NOTE: These badge ids are not in order! They are grouped logically.
  #       When picking an id, *search* for it.

  BasicUser = 1
  Member = 2
  Regular = 3
  Leader = 4

  Welcome = 5
  NicePost = 6
  GoodPost = 7
  GreatPost = 8
  Autobiographer = 9
  Editor = 10
  WikiEditor = 48

  FirstLike = 11
  FirstShare = 12
  FirstFlag = 13
  FirstLink = 14
  FirstQuote = 15
  FirstMention = 40
  FirstEmoji = 41
  FirstOnebox = 42
  FirstReplyByEmail = 43

  ReadGuidelines = 16
  Reader = 17
  NiceTopic = 18
  GoodTopic = 19
  GreatTopic = 20
  NiceShare = 21
  GoodShare = 22
  GreatShare = 23
  Anniversary = 24

  Promoter = 25
  Campaigner = 26
  Champion = 27

  PopularLink = 28
  HotLink = 29
  FamousLink = 30

  Appreciated = 36
  Respected = 37
  Admired = 31

  OutOfLove = 33
  HigherLove = 34
  CrazyInLove = 35

  ThankYou = 38
  GivesBack = 32
  Empathetic = 39

  Enthusiast = 45
  Aficionado = 46
  Devotee = 47

  NewUserOfTheMonth = 44

  # other consts
  AutobiographerMinBioLength = 10

  # used by serializer
  attr_accessor :has_badge

  def self.trigger_hash
    @trigger_hash ||=
      Badge::Trigger
        .constants
        .map do |k|
          name = k.to_s.underscore
          [name, Badge::Trigger.const_get(k)] unless name =~ /deprecated/
        end
        .compact
        .to_h
  end

  module Trigger
    None = 0
    PostAction = 1
    PostRevision = 2
    TrustLevelChange = 4
    UserChange = 8
    DeprecatedPostProcessed = 16 # No longer in use

    def self.is_none?(trigger)
      [None].include? trigger
    end

    def self.uses_user_ids?(trigger)
      [TrustLevelChange, UserChange].include? trigger
    end

    def self.uses_post_ids?(trigger)
      [PostAction, PostRevision].include? trigger
    end
  end

  belongs_to :badge_type
  belongs_to :badge_grouping
  belongs_to :image_upload, class_name: "Upload"

  has_many :user_badges, dependent: :destroy
  has_many :upload_references, as: :target, dependent: :destroy

  validate :plugin_badge_key_is_immutable, on: :update

  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :badge_type, presence: true
  validates :allow_title, inclusion: [true, false]
  validates :multiple_grant, inclusion: [true, false]
  validates :description, length: { maximum: 500 }
  validates :long_description, length: { maximum: 1000 }

  scope :enabled, -> { where(enabled: true) }

  before_save :sanitize_description
  before_create :ensure_not_system

  after_save do
    if saved_change_to_image_upload_id?
      UploadReference.ensure_exist!(upload_ids: [image_upload_id], target: self)
    end
  end

  after_commit do
    SvgSprite.expire_cache
    UserStat.update_distinct_badge_count if saved_change_to_enabled?
    UserBadge.ensure_consistency! if saved_change_to_enabled?
  end

  # The namespaced key records ownership; the numeric ID is the seed identity.
  # In particular, never turn a site's badge into a plugin badge just because
  # its display name happens to match. Legacy adoption is deliberately stricter.
  def self.seed_plugin(
    key,
    name:,
    legacy_names: [name],
    legacy_groupings: [],
    legacy_queries: [],
    adopt_legacy: true,
    &definition
  )
    unless key.match?(/\A[a-z0-9_-]+:[a-z0-9_-]+\z/)
      raise ArgumentError, "expected a namespaced plugin badge key"
    end

    transaction do
      # Badge IDs are allocated from MAX(id), so serialize plugin seeds, including
      # seeds of different keys. The unique index is the final ownership guard.
      DB.exec("SELECT pg_advisory_xact_lock(hashtext('discourse_badge_ids'))")
      badge = find_by(plugin_badge_key: key)

      if !badge && adopt_legacy
        expected = new(name: name, system: true)
        definition.call(expected)
        candidates = where(plugin_badge_key: nil, system: true, name: legacy_names).to_a
        candidates.select! do |candidate|
          %w[
            badge_type_id
            multiple_grant
            target_posts
            show_posts
            trigger
            auto_revoke
            listable
          ].all? { |field| candidate[field] == expected[field] } &&
            ([expected.query] + legacy_queries)
              .map { |query| query&.strip }
              .include?(candidate.query&.strip) &&
            (
              expected.query.present? ||
                (
                  legacy_groupings.include?(candidate.badge_grouping&.name) &&
                    candidate.icon == expected.icon
                )
            )
        end
        badge = candidates.first if candidates.one?
      end

      if !badge && where(name: name).exists?
        Rails.logger.warn(
          "Skipped plugin badge #{key.inspect}: the name #{name.inspect} is already in use",
        )
        next
      end

      badge ||= new(name: name, system: true)
      # Persist the local ID once, retaining historical grants, links and titles.
      # Further seeds find the ID through ownership, never through a display name.
      if badge.new_record?
        definition.call(badge)
        badge.plugin_badge_key = key
        badge.save!
      else
        badge.update!(plugin_badge_key: key) if badge.plugin_badge_key.nil?
      end

      seed(:id) do |seeded|
        seeded.id = badge.id
        # An existing, site-renamed badge keeps its name if the new default is
        # occupied. Do not rewrite the unrelated badge or fail the whole upgrade.
        seeded.name = where.not(id: badge.id).exists?(name: name) ? badge.name : name
        seeded.system = true
        definition.call(seeded)
      end
      find(badge.id)
    end
  end

  # fields that can not be edited on system badges
  def self.protected_system_fields
    %i[name badge_type_id multiple_grant target_posts show_posts query trigger auto_revoke listable]
  end

  def self.trust_level_badge_ids
    (1..4).to_a
  end

  def self.like_badge_counts
    @like_badge_counts ||= {
      NicePost => 10,
      GoodPost => 25,
      GreatPost => 50,
      NiceTopic => 10,
      GoodTopic => 25,
      GreatTopic => 50,
    }
  end

  def self.ensure_consistency!
    DB.exec <<~SQL
      DELETE FROM user_badges
            USING user_badges ub
        LEFT JOIN users u ON u.id = ub.user_id
            WHERE u.id IS NULL
              AND user_badges.id = ub.id
    SQL

    DB.exec <<~SQL
      WITH X AS (
          SELECT badge_id
               , COUNT(user_id) users
            FROM user_badges
        GROUP BY badge_id
      )
      UPDATE badges
         SET grant_count = X.users
        FROM X
       WHERE id = X.badge_id
         AND grant_count <> X.users
    SQL
  end

  def clear_user_titles!
    DB.exec(<<~SQL, badge_id: id, updated_at: Time.zone.now)
      UPDATE users AS u
      SET title = '', updated_at = :updated_at
      FROM user_profiles AS up
      WHERE up.user_id = u.id AND up.granted_title_badge_id = :badge_id
    SQL
    DB.exec(<<~SQL, badge_id: id)
      UPDATE user_profiles AS up
      SET granted_title_badge_id = NULL
      WHERE up.granted_title_badge_id = :badge_id
    SQL
  end

  ##
  # Update all user titles based on a badge to the new name
  def update_user_titles!(new_title)
    DB.exec(<<~SQL, granted_title_badge_id: id, title: new_title, updated_at: Time.zone.now)
      UPDATE users AS u
      SET title = :title, updated_at = :updated_at
      FROM user_profiles AS up
      WHERE up.user_id = u.id AND up.granted_title_badge_id = :granted_title_badge_id
    SQL
  end

  ##
  # When a badge has its TranslationOverride cleared, reset
  # all user titles granted to the standard name.
  def reset_user_titles!
    DB.exec(<<~SQL, granted_title_badge_id: id, updated_at: Time.zone.now)
      UPDATE users AS u
      SET title = badges.name, updated_at = :updated_at
      FROM user_profiles AS up
      INNER JOIN badges ON badges.id = up.granted_title_badge_id
      WHERE up.user_id = u.id AND up.granted_title_badge_id = :granted_title_badge_id
    SQL
  end

  def self.i18n_name(name)
    name.to_s.downcase.tr(" ", "_")
  end

  def self.display_name(name)
    I18n.t(i18n_key(name), default: name)
  end

  def self.i18n_key(name)
    "badges.#{i18n_name(name)}.name"
  end

  def self.find_system_badge_id_from_translation_key(translation_key)
    return unless translation_key.starts_with?("badges.")
    badge_name_klass = translation_key.split(".").second.camelize
    Badge.const_defined?(badge_name_klass) ? "Badge::#{badge_name_klass}".constantize : nil
  end

  def awarded_for_trust_level?
    id <= 4
  end

  def reset_grant_count!
    self.grant_count = UserBadge.where(badge_id: id).count
    save!
  end

  def single_grant?
    !multiple_grant?
  end

  def default_icon=(val)
    if image_upload_id.blank?
      self.icon ||= val
      self.icon = val if icon == "certificate"
    end
  end

  def default_allow_title=(val)
    return if !new_record?
    self.allow_title = val
  end

  def default_enabled=(val)
    return if !new_record?
    self.enabled = val
  end

  def default_badge_grouping_id=(val)
    # allow to correct orphans
    self.badge_grouping_id = val if !badge_grouping_id || badge_grouping_id <= BadgeGrouping::Other
  end

  def display_name
    return name if !has_attribute?(:system) || !system?

    self.class.display_name(name)
  end

  def translation_key
    self.class.i18n_key(name)
  end

  def long_description
    return self[:long_description] || "" if !has_attribute?(:system) || !system?

    key = "badges.#{i18n_name}.long_description"
    I18n.t(
      key,
      default: self[:long_description] || "",
      base_uri: Discourse.base_path,
      max_likes_per_day: SiteSetting.max_likes_per_day,
    )
  end

  def long_description=(val)
    self[:long_description] = val if val != long_description
  end

  def description
    return self[:description] || "" if !has_attribute?(:system) || !system?

    key = "badges.#{i18n_name}.description"
    I18n.t(
      key,
      default: self[:description] || "",
      base_uri: Discourse.base_path,
      max_likes_per_day: SiteSetting.max_likes_per_day,
    )
  end

  def description=(val)
    self[:description] = val if val != description
  end

  def slug
    Slug.for(display_name, "-")
  end

  def manually_grantable?
    !system?
  end

  def i18n_name
    @i18n_name ||= self.class.i18n_name(name)
  end

  def image_url
    upload_cdn_path(image_upload.url) if image_upload_id.present?
  end

  def for_beginners?
    id == Welcome || (badge_grouping_id == BadgeGrouping::GettingStarted && id != NewUserOfTheMonth)
  end

  protected

  def plugin_badge_key_is_immutable
    if will_save_change_to_plugin_badge_key? && plugin_badge_key_in_database.present?
      errors.add(:plugin_badge_key, "cannot change once assigned")
    end
  end

  def ensure_not_system
    if !id
      DB.exec("SELECT pg_advisory_xact_lock(hashtext('discourse_badge_ids'))")
      self.id = [Badge.maximum(:id) + 1, 100].max
    end
  end

  def sanitize_description
    self.description = sanitize_field(description) if description_changed?
  end
end

# == Schema Information
#
# Table name: badges
#
#  id                  :integer          not null, primary key
#  allow_title         :boolean          default(FALSE), not null
#  auto_revoke         :boolean          default(TRUE), not null
#  description         :text
#  enabled             :boolean          default(TRUE), not null
#  grant_count         :integer          default(0), not null
#  icon                :string           default("certificate")
#  listable            :boolean          default(TRUE)
#  long_description    :text
#  multiple_grant      :boolean          default(FALSE), not null
#  name                :string           not null
#  query               :text
#  show_in_post_header :boolean          default(FALSE), not null
#  show_posts          :boolean          default(FALSE), not null
#  system              :boolean          default(FALSE), not null
#  target_posts        :boolean          default(FALSE)
#  trigger             :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  badge_grouping_id   :integer          default(5), not null
#  badge_type_id       :integer          not null
#  image_upload_id     :integer
#
# Indexes
#
#  index_badges_on_badge_type_id  (badge_type_id)
#  index_badges_on_name           (name) UNIQUE
#
