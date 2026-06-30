# frozen_string_literal: true

# Schema class generation moved to the avro-gen-ruby gem. These specs cover the
# backwards-compatible shims that keep the old Deimos constants working for
# users who haven't yet run `rake avro:upgrade`.
RSpec.describe Deimos::SchemaClass do
  describe 'deprecated constants' do
    it 'resolves to the AvroGen equivalents' do
      expect(Deimos::SchemaClass::Base).to be(AvroGen::SchemaClass::Base)
      expect(Deimos::SchemaClass::Record).to be(AvroGen::SchemaClass::Record)
      expect(Deimos::SchemaClass::Enum).to be(AvroGen::SchemaClass::Enum)
    end

    it 'emits a deprecation warning when an old constant is referenced' do
      allow(Deimos::Logging).to receive(:deprecate)
      # Stub const_set so re-resolving doesn't emit an "already initialized" warning.
      allow(described_class).to receive(:const_set)

      expect(described_class.const_missing(:Record)).to be(AvroGen::SchemaClass::Record)
      expect(Deimos::Logging).to have_received(:deprecate).
        with(a_string_matching(/Deimos::SchemaClass::Record is deprecated/))
    end

    it 'raises NameError for genuinely unknown constants' do
      expect { Deimos::SchemaClass::NotARealClass }.to raise_error(NameError)
    end
  end

  describe Deimos::Utils::SchemaClass do
    it 'delegates to AvroGen::SchemaClass with a deprecation warning' do
      allow(Deimos::Logging).to receive(:deprecate)

      expect(described_class.modules_for('com.my-namespace')).
        to eq(AvroGen::SchemaClass.modules_for('com.my-namespace'))
      expect(Deimos::Logging).to have_received(:deprecate).
        with(a_string_matching(/Deimos::Utils::SchemaClass\.modules_for is deprecated/))
    end

    it 'still raises NoMethodError for genuinely unknown methods' do
      expect { described_class.not_a_real_method }.to raise_error(NoMethodError)
    end
  end

  describe 'generation config' do
    it 'forwards Deimos.config.avrogen settings to AvroGen.config' do
      Deimos.configure do |config|
        config.avrogen.generated_class_path = 'custom/classes'
        config.avrogen.use_full_namespace = true
      end

      expect(AvroGen.config.generated_class_path).to eq('custom/classes')
      expect(AvroGen.config.use_full_namespace).to be(true)
    end

    it 'still honors the legacy schema setting, deprecating it in favour of avrogen' do
      allow(Deimos::Logging).to receive(:deprecate)

      Deimos.configure { |config| config.schema.generated_class_path = 'legacy/classes' }

      expect(AvroGen.config.generated_class_path).to eq('legacy/classes')
      expect(Deimos::Logging).to have_received(:deprecate).
        with(a_string_matching(/Deimos\.config\.schema\.generated_class_path is deprecated.*avrogen/))
    end
  end
end
