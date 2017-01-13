module Commands
  module V2
    class UpdateExistingDraftContentItem
      ATTRIBUTES_PROTECTED_FROM_RESET = [
        :id,
        :created_at,
        :updated_at,
        :first_published_at,
        :last_edited_at,
      ].freeze

      attr_reader :payload, :put_content, :content_item

      def initialize(content_item, put_content, payload)
        @content_item = content_item
        @put_content = put_content
        @payload = payload
      end

      def call
        update_existing_content_item
        content_item
      end

      def update_existing_content_item
        version = put_content.check_version_and_raise_if_conflicting(content_item, payload[:previous_version])

        update_content_item

        version.increment!
      end

      def update_content_item
        assign_attributes_with_defaults(
          content_item_attributes_from_payload.merge( locale: payload.fetch(:locale, ContentItem::DEFAULT_LOCALE),
                                                     state: "draft",
                                                     content_store: "draft",
                                                     user_facing_version: content_item.user_facing_version,
                                                    )
        )
        content_item.save!
      end

      def assign_attributes_with_defaults(attributes)
        new_attributes = content_item.class.column_defaults.symbolize_keys
        .merge(attributes.symbolize_keys)
        .except(*ATTRIBUTES_PROTECTED_FROM_RESET)
        content_item.assign_attributes(new_attributes)
      end

      def content_item_attributes_from_payload
        payload.slice(*ContentItem::TOP_LEVEL_FIELDS)
      end
    end
  end
end
