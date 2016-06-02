require "rails_helper"

RSpec.describe PresentedContentStoreWorker do
  let(:content_item) { FactoryGirl.create(:live_content_item, base_path: "/foo") }

  before do
    stub_request(:put, %r{.*content-store.*/content/.*})
  end

  describe "raised errors" do
    before do
      stub_request(:put, "http://content-store.dev.gov.uk/content/foo").
        to_return(status: status, body: {}.to_json)
    end

    def do_request
      subject.perform(
        content_store: "Adapters::ContentStore",
        payload: { content_item_id: content_item.id, payload_version: "1" }
      )
    end

    expectations = {
      200 => { raises_error: false, logs_to_airbrake: false },
      202 => { raises_error: false, logs_to_airbrake: false },
      400 => { raises_error: false, logs_to_airbrake: true },
      409 => { raises_error: false, logs_to_airbrake: false },
      500 => { raises_error: true, logs_to_airbrake: false },
    }

    expectations.each do |status, expectation|
      context "when the content store responds with a #{status}" do
        let(:status) { status }

        if expectation.fetch(:raises_error)
          it "raises an error" do
            expect { do_request }.to raise_error(CommandError)
          end
        else
          it "does not raise an error" do
            expect { do_request }.to_not raise_error
          end
        end

        if expectation.fetch(:logs_to_airbrake)
          it "logs the response to airbrake" do
            expect(Airbrake).to receive(:notify_or_ignore)
            do_request rescue CommandError
          end
        else
          it "does not log the response to airbrake" do
            expect(Airbrake).to_not receive(:notify_or_ignore)
            do_request rescue CommandError
          end
        end
      end
    end
  end

  describe "draft-to-live protection" do
    it "prevents draft content items being sent to the live content store" do
      draft = FactoryGirl.create(:draft_content_item)

      expect {
        subject.perform(
          content_store: "Adapters::ContentStore",
          payload: { content_item_id: draft.id, payload_version: "1" }
        )
      }.to raise_error(CommandError)
    end

    it "allows draft content items to be sent to the draft content store" do
      draft = FactoryGirl.create(:draft_content_item)

      expect {
        subject.perform(
          content_store: "Adapters::DraftContentStore",
          payload: { content_item_id: draft.id, payload_version: "1" }
        )
      }.not_to raise_error
    end

    it "allows live content items to be sent to the live content store" do
      live = FactoryGirl.create(:live_content_item)

      expect {
        subject.perform(
          content_store: "Adapters::ContentStore",
          payload: { content_item_id: live.id, payload_version: "1" }
        )
      }.not_to raise_error
    end

    it "allows live content items to be sent to the draft content store" do
      live = FactoryGirl.create(:live_content_item)

      expect {
        subject.perform(
          content_store: "Adapters::DraftContentStore",
          payload: { content_item_id: live.id, payload_version: "1" }
        )
      }.not_to raise_error
    end
  end
end
