# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::MassUpdater do

    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.integer(:some_int)
        t.string(:bulk_import_id)
        t.timestamps
      end

      # create one-to-one association -- Details
      ActiveRecord::Base.connection.create_table(:details, force: true) do |t|
        t.string(:title)
        t.string(:bulk_import_id)
        t.belongs_to(:widget)

        t.index(%i(title), unique: true)
      end
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
      ActiveRecord::Base.connection.drop_table(:details)
    end

    let(:detail_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'details'
        belongs_to :widget
      end
    end

    let(:widget_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'widgets'
        has_one :detail
      end
    end

    let(:bulk_id_generator) { proc { SecureRandom.uuid } }

    before(:each) do
      stub_const('Widget', widget_class)
      stub_const('Detail', detail_class)
      Widget.reset_column_information
    end

    describe '#mass_update' do
      let(:batch) do
        Deimos::ActiveRecordConsume::BatchRecordList.new(
          [
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Widget,
              attributes: { test_id: 'id1', some_int: 5, detail: { title: 'Title 1' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            ),
            Deimos::ActiveRecordConsume::BatchRecord.new(
              klass: Widget,
              attributes: { test_id: 'id2', some_int: 10, detail: { title: 'Title 2' } },
              bulk_import_column: 'bulk_import_id',
              bulk_import_id_generator: bulk_id_generator
            )
          ]
        )
      end

      it 'should mass update the batch' do
        allow(SecureRandom).to receive(:uuid).and_return('1', '2')
        described_class.new(Widget).mass_update(batch)
        expect(Widget.count).to eq(2)
        expect(Widget.all.to_a.map(&:bulk_import_id)).to match(%w(1 2))
        expect(Detail.count).to eq(2)
        expect(Widget.first.detail).not_to be_nil
        expect(Widget.last.detail).not_to be_nil
      end

    end
end
