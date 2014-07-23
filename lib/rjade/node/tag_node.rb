require_relative 'base_node'

module RJade

	class TagNode < Node
		register_type :tag

		attr_forw_accessor :name, :data

		# @return [Array<TagAttributeNode>]
		#
		attr_reader :attributes

		def initialize(*args)
			super(*args)

			@attributes = []
		end

		# @param [Node] node
		#
		def << (node)
			if node.type == :tag_attribute
				@attributes << node
			else
				super
			end
		end
	end


	class TagAttributeNode < Node
		register_type :tag_attribute

		attr_forw_accessor :name, :data

		attr_accessor :value
	end
end