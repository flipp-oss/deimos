# frozen_string_literal: true

# :nodoc:
class MyConfig
  include Deimos::Configurable

  define_settings do
    setting :set1
    setting :set2, 'hi mom'
    setting :group do
      setting :set3, default_proc: proc { false }
      setting :set5, (proc { 5 })
    end

    setting_object :listy do
      setting :list1, 10
      setting :list2, 5
    end
  end
end

describe Deimos::Configurable do
  it 'should configure correctly with default values' do
    expect(MyConfig.config.set1).to be_nil
    expect(MyConfig.config.set2).to eq('hi mom')
    expect(MyConfig.config.group.set3).to eq(false)
    expect(MyConfig.config.listy_objects).to be_empty
    expect { MyConfig.config.blah }.to raise_error(NameError)
    expect { MyConfig.config.group.set4 }.to raise_error(NameError)
  end

  it 'should not call the proc until it has to' do
    num_calls = 0
    value_proc = proc do
      num_calls += 1
      num_calls
    end
    MyConfig.define_settings do
      setting :set_with_proc, default_proc: value_proc
    end
    expect(num_calls).to eq(0)
    expect(MyConfig.config.set_with_proc).to eq(1)
    # calling twice should not call the proc again
    expect(MyConfig.config.set_with_proc).to eq(1)
    expect(num_calls).to eq(1)
  end

  it "should raise error when setting configs that don't exist" do
    expect { MyConfig.configure { set15 'some_value' } }.to raise_error(NameError)
  end

  it 'should add values' do
    MyConfig.configure do |config|
      config.set1 = 5 # config.x syntax
      set2 nil # method_missing syntax
      config.group.set3 = true
    end

    # second configure should not blow anything away
    MyConfig.configure do
      listy do
        list1 0
        list2 1
      end
      listy do
        list1 100
        list2 200
      end
    end

    expect(MyConfig.config.set1).to eq(5)
    expect(MyConfig.config.set2).to be_nil
    expect(MyConfig.config.group.set3).to eq(true)
    expect(MyConfig.config.listy_objects.map(&:to_h)).
      to eq([
              { list1: 0, list2: 1 },
              { list1: 100, list2: 200 }
            ])

    # test reset!
    MyConfig.config.reset!
    expect(MyConfig.config.set1).to be_nil
    expect(MyConfig.config.set2).to eq('hi mom')
    expect(MyConfig.config.group.set3).to eq(false)
    expect(MyConfig.config.listy_objects).to be_empty
  end

  it 'should add with block syntax' do
    MyConfig.configure do
      group do
        set5(proc { 10 })
      end
    end
    expect(MyConfig.config.group.set5.call).to eq(10)
  end

  it 'should add or redefine settings' do
    MyConfig.define_settings do
      setting :group do
        setting :set6, 15
        setting :set5, (proc { 15 })
      end
      setting_object :notey do
        setting :note_title, 'some-title'
      end
    end

    expect(MyConfig.config.group.set6).to eq(15)
    expect(MyConfig.config.group.set5.call).to eq(15)
    expect(MyConfig.config.listy_objects).to be_empty
    expect(MyConfig.config.notey_objects).to be_empty

    MyConfig.configure do
      notey do
        note_title 'hi mom'
      end
      listy do
        list1 0
      end
    end
    expect(MyConfig.config.notey_objects.size).to eq(1)
    expect(MyConfig.config.notey_objects.first.note_title).to eq('hi mom')
    expect(MyConfig.config.listy_objects.size).to eq(1)
    expect(MyConfig.config.listy_objects.first.list1).to eq(0)

    # This should not remove any keys
    MyConfig.define_settings do
      setting :group do
        setting :set6, 20
      end
    end
    expect(MyConfig.config.group.set6).to eq(20)
    expect(MyConfig.config.group.set5.call).to eq(15)
  end

end
