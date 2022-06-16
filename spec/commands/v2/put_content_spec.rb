RSpec.describe Commands::V2::PutContent do
  describe "call" do
    before do
      stub_request(:delete, %r{.*content-store.*/content/.*})
      stub_request(:put, %r{.*content-store.*/content/.*})
    end

    let(:content_id) { SecureRandom.uuid }
    let(:new_content_id) { SecureRandom.uuid }
    let(:base_path) { "/vat-rates" }
    let(:locale) { "en" }
    let(:publishing_app) { "publisher" }

    let(:change_note) { "Info" }
    let(:new_change_note) { "Changed Info" }
    let(:payload) do
      {
        content_id: content_id,
        base_path: base_path,
        update_type: "major",
        title: "Some Title",
        publishing_app: publishing_app,
        rendering_app: "frontend",
        document_type: "services_and_information",
        schema_name: "generic",
        locale: locale,
        routes: [{ path: base_path, type: "exact" }],
        redirects: [],
        phase: "beta",
        change_note: change_note,
        details: {},
      }
    end

    let(:updated_payload) do
      {
        content_id: content_id,
        base_path: base_path,
        update_type: "major",
        title: "New Title",
        publishing_app: publishing_app,
        rendering_app: "frontend",
        document_type: "services_and_information",
        schema_name: "generic",
        locale: locale,
        routes: [{ path: base_path, type: "exact" }],
        redirects: [],
        phase: "beta",
        change_note: new_change_note,
        details: {},
      }
    end

    it "validates the payload" do
      validator = double(:validator)
      expect(Commands::V2::PutContentValidator).to receive(:new)
        .with(payload, instance_of(described_class))
        .and_return(validator)
      expect(validator).to receive(:validate)
      expect(PathReservation).to receive(:reserve_base_path!)
      expect { described_class.call(payload) }.not_to raise_error
    end

    it "sends to the downstream draft worker" do
      expect(DownstreamDraftWorker).to receive(:perform_async_in_queue)
        .with(
          "downstream_high",
          a_hash_including(
            :content_id,
            :locale,
            update_dependencies: true,
            source_command: "put_content",
            source_fields: [],
          ),
        )

      described_class.call(payload)
    end

    it "sends to the downstream draft worker only the fields which have changed" do
      described_class.call(payload)

      expect(DownstreamDraftWorker)
        .to receive(:perform_async_in_queue)
        .with("downstream_high", a_hash_including(source_fields: %i[title]))

      described_class.call(updated_payload)
    end

    it "does not send to the downstream live worker" do
      expect(DownstreamLiveWorker).not_to receive(:perform_async_in_queue)
      described_class.call(payload)
    end

    it "creates an action" do
      expect(Action.count).to be 0
      described_class.call(payload)
      expect(Action.count).to be 1
      described_class.call(updated_payload)
      expect(Action.last.attributes).to match a_hash_including(
        "content_id" => content_id,
        "locale" => locale,
        "action" => "PutContent",
      )
    end

    context "when the 'downstream' parameter is false" do
      it "does not send to the downstream draft worker" do
        expect(DownstreamDraftWorker).not_to receive(:perform_async_in_queue)

        described_class.call(payload, downstream: false)
      end
    end

    context "when the 'bulk_publishing' flag is set" do
      it "enqueues in the correct queue" do
        expect(DownstreamDraftWorker).to receive(:perform_async_in_queue)
          .with(
            "downstream_low",
            anything,
          )

        described_class.call(payload.merge(bulk_publishing: true))
      end
    end

    context "when the payload includes auth_bypass_ids" do
      it "updates edition with access_limits auth_bypass_ids" do
        auth_bypass_id = SecureRandom.uuid
        payload.merge!(access_limited: { auth_bypass_ids: [auth_bypass_id] })

        expect { described_class.call(payload) }.to_not change(AccessLimit, :count)
        expect(Edition.last.auth_bypass_ids).to eq([auth_bypass_id])
      end

      it "updates edition with root auth_bypass_ids" do
        payload.merge!(auth_bypass_ids: [SecureRandom.uuid])

        described_class.call(payload)
        expect(Edition.last.auth_bypass_ids).to eq(payload[:auth_bypass_ids])
      end

      it "updates edition with root auth_bypass_ids over access_limits" do
        payload.merge!(
          auth_bypass_ids: [SecureRandom.uuid],
          access_limited: { auth_bypass_ids: [SecureRandom.uuid] },
        )

        described_class.call(payload)
        expect(Edition.last.auth_bypass_ids).to eq(payload[:auth_bypass_ids])
      end
    end

    it_behaves_like TransactionalCommand

    context "when the draft does not exist" do
      context "with a provided last_edited_at" do
        it "stores the provided timestamp" do
          last_edited_at = 1.year.ago

          described_class.call(payload.merge(last_edited_at: last_edited_at.iso8601))

          edition = Edition.last

          expect(edition.last_edited_at.iso8601).to eq(last_edited_at.iso8601)
        end
      end

      it "stores last_edited_at as the current time" do
        Timecop.freeze do
          described_class.call(payload)

          edition = Edition.last

          expect(edition.last_edited_at.iso8601).to eq(Time.zone.now.iso8601)
        end
      end

      context "when the payload includes an access limit" do
        let(:auth_bypass_id) { SecureRandom.uuid }
        let(:organisation_id) { SecureRandom.uuid }
        before do
          payload.merge!(access_limited: {
            users: %w[new-user],
            organisations: [organisation_id],
          })
        end

        it "creates a new access limit" do
          expect {
            described_class.call(payload)
          }.to change(AccessLimit, :count).by(1)

          access_limit = AccessLimit.last
          expect(access_limit.users).to eq(%w[new-user])
          expect(access_limit.organisations).to eq([organisation_id])
          expect(access_limit.edition).to eq(Edition.last)
        end
      end

      context "when the payload doesn't include an access limit" do
        it "creates a new access limit" do
          described_class.call(payload)
          expect(AccessLimit.count).to eq(0)
        end
      end
    end

    context "when the draft does exist" do
      let(:document) { create(:document, content_id: content_id) }
      let!(:edition) { create(:draft_edition, document: document) }

      context "with a provided last_edited_at" do
        %w[minor major republish].each do |update_type|
          context "with update_type of #{update_type}" do
            it "stores the provided timestamp" do
              last_edited_at = 1.year.ago

              described_class.call(
                payload.merge(
                  update_type: update_type,
                  last_edited_at: last_edited_at.iso8601,
                ),
              )

              expect(edition.reload.last_edited_at.iso8601).to eq(last_edited_at.iso8601)
            end
          end
        end
      end

      it "stores last_edited_at as the current time" do
        Timecop.freeze do
          described_class.call(payload)

          expect(edition.reload.last_edited_at.iso8601).to eq(Time.zone.now.iso8601)
        end
      end

      it "deletes a previous path reservation if the paths differ" do
        edition.update!(base_path: "/different", routes: [{ path: "/different", type: "exact" }])
        create(:path_reservation, base_path: "/different", publishing_app: publishing_app)
        expect { described_class.call(payload) }
          .to change { PathReservation.where(base_path: "/different").count }
          .by(-1)
      end

      it "doesn't delete a previous path reservation if the paths are the same" do
        edition.update!(base_path: base_path, routes: [{ path: base_path, type: "exact" }])
        create(:path_reservation, base_path: base_path, publishing_app: publishing_app)
        expect { described_class.call(payload) }
          .not_to(change { PathReservation.where(base_path: base_path).count })
      end

      it "doesn't delete a previous path reservation if it is registered to a different publishing application" do
        edition.update!(base_path: "/different", routes: [{ path: "/different", type: "exact" }])
        create(:path_reservation, base_path: "/different", publishing_app: "different")
        expect { described_class.call(payload) }
          .not_to(change { PathReservation.where(base_path: "/different").count })
      end

      it "doesn't delete a previous path reservation if it's used by a live "\
        "edition published by the same app" do
        edition.update!(base_path: "/different",
                        routes: [{ path: "/different", type: "exact" }])
        create(:live_edition, base_path: "/different", publishing_app: publishing_app)
        create(:path_reservation, base_path: "/different", publishing_app: publishing_app)
        expect { described_class.call(payload) }
          .not_to(change { PathReservation.where(base_path: "/different").count })
      end

      it "deletes a previous path reservation if it's used by a live "\
        "edition published by a different app" do
        edition.update!(base_path: "/different",
                        routes: [{ path: "/different", type: "exact" }])
        create(:live_edition, base_path: "/different", publishing_app: "different-app")
        create(:path_reservation, base_path: "/different", publishing_app: publishing_app)
        expect { described_class.call(payload) }
          .to change { PathReservation.where(base_path: "/different").count }
          .by(-1)
      end

      context "when the existing draft doesn't have access limit" do
        let(:auth_bypass_id) { SecureRandom.uuid }
        let(:organisation_id) { SecureRandom.uuid }
        before do
          payload.merge!(access_limited: {
            users: %w[new-user],
            organisations: [organisation_id],
          })
        end

        it "creates a new access limit" do
          expect {
            described_class.call(payload)
          }.to change(AccessLimit, :count).by(1)
          access_limit = AccessLimit.last
          expect(access_limit.users).to eq(%w[new-user])
          expect(access_limit.organisations).to eq([organisation_id])
          expect(access_limit.edition).to eq(edition)
        end
      end

      context "when the payload doesn't include an access limit" do
        it "creates a new access limit" do
          described_class.call(payload)
          expect(AccessLimit.count).to eq(0)
        end
      end

      context "when the existing draft has access limits" do
        let!(:access_limit) { create(:access_limit, edition: edition) }

        context "when the payload doesn't include an access limit" do
          it "removes the access limits" do
            described_class.call(payload)
            expect(AccessLimit.count).to eq(0)
          end
        end

        context "when the payload includes an access limit" do
          let(:auth_bypass_id) { SecureRandom.uuid }
          let(:organisation_id) { SecureRandom.uuid }
          before do
            payload.merge!(access_limited: {
              users: %w[new-user],
              organisations: [organisation_id],
            })
          end

          it "updates the existing access limit" do
            described_class.call(payload)
            access_limit.reload
            expect(access_limit.users).to eq(%w[new-user])
            expect(access_limit.organisations).to eq([organisation_id])
          end
        end
      end
    end

    context "when a draft does exist with a different locale" do
      let(:en_document) { create(:document, content_id: content_id) }
      let!(:en_edition) do
        create(:draft_edition, base_path: base_path, document: en_document)
      end

      it "replaces the old draft with the new one" do
        expect {
          described_class.call(payload.merge(locale: "cy"))
        }.not_to raise_error

        expect {
          Edition.find(en_edition.id)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "field doesn't change between drafts" do
      it "doesn't update the dependencies" do
        expect(DownstreamDraftWorker).to receive(:perform_async_in_queue)
          .with(anything, a_hash_including(update_dependencies: true))
        expect(DownstreamDraftWorker).to receive(:perform_async_in_queue)
          .with(anything, a_hash_including(update_dependencies: false))
        described_class.call(payload)
        described_class.call(payload)
      end
    end

    context "when no update_type is provided" do
      before do
        payload.delete(:update_type)
      end

      it "should send an alert to GovukError" do
        expect(GovukError).to receive(:notify)
          .with(anything, level: "warning", extra: a_hash_including(content_id: content_id))

        described_class.call(payload)
      end
    end

    context "when an update type is provided" do
      it "should not send an alert to GovukError" do
        expect(GovukError).to_not receive(:notify)
          .with(anything, level: "warning", extra: a_hash_including(content_id: content_id))

        described_class.call(payload)
      end
    end
  end
end
