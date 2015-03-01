
require_relative '../../lib/bade/renderer'

describe Bade::Renderer do
  it 'supports simple rendering from source string' do
    output = Bade::Renderer.from_source('a some text')
                           .render(new_line: '')
    expect(output).to eq('<a>some text</a>')
  end

  it 'supports simple rendering from source string with locals' do
    output = Bade::Renderer.from_source('a= magic')
                           .with_locals(magic: 'magic string')
                           .render(new_line: '')

    expect(output).to eq('<a>magic string</a>')
  end

  it 'supports simple rendering from file path' do
    output = Bade::Renderer.from_file(File.join(File.dirname(__FILE__), 'from_file.bade'))
                           .with_locals(magic: 'woohoo')
                           .render(new_line: '')

    expect(output).to eq('<a class="some">text</a>woohoo')
  end

  it 'supports simple rendering from file obj' do
    output = Bade::Renderer.from_file(File.new(File.join(File.dirname(__FILE__), 'from_file.bade'), 'r'))
                           .with_locals(magic: 'woohoo')
                           .render(new_line: '')

    expect(output).to eq('<a class="some">text</a>woohoo')
  end
end
