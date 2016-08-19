class DependencyResolutionWorker
  include Sidekiq::Worker
  include PerformAsyncInQueue

  sidekiq_options queue: :dependency_resolution

  def perform(args = {})
    assign_attributes(args.deep_symbolize_keys)

    content_item_dependees.each do |dependent_content_id|
      downstream_content_item(dependent_content_id)
    end
  end

private

  attr_reader :content_id, :fields, :content_store, :payload_version

  def assign_attributes(args)
    @content_id = args.fetch(:content_id)
    @fields = args.fetch(:fields, []).map(&:to_sym)
    @content_store = args.fetch(:content_store).constantize
    @payload_version = args.fetch(:payload_version)
  end

  def content_item_dependees
    Queries::ContentDependencies.new(content_id: content_id,
                                     fields: fields,
                                     dependent_lookup: Queries::GetDependees.new).call
  end

  def downstream_content_item(dependent_content_id)
    scope = ContentItem.where(content_id: dependent_content_id)
    if draft?
      latest_content_item = Queries::GetLatest.call(scope).last
    else
      latest_content_item = ContentItemFilter.new(scope: scope).filter(state: "published").last
    end

    return unless latest_content_item

    if draft?
      downstream_draft(latest_content_item)
    else
      downstream_live(latest_content_item)
    end
  end

  def draft?
    content_store == Adapters::DraftContentStore
  end

  def downstream_draft(latest_content_item)
    DownstreamDraftWorker.perform_async_in_queue(
      DownstreamDraftWorker::LOW_QUEUE,
      content_item_id: latest_content_item.id,
      payload_version: payload_version,
      update_dependencies: false,
      alert_on_invalid_state_error: false,
    )
  end

  def downstream_live(latest_content_item)
    DownstreamLiveWorker.perform_async_in_queue(
      DownstreamLiveWorker::LOW_QUEUE,
      content_item_id: latest_content_item.id,
      message_queue_update_type: "links",
      payload_version: payload_version,
      update_dependencies: false,
      alert_on_invalid_state_error: false,
    )
  end
end
