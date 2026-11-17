module Caracal
  module Md
    # Helpers for numbering instances (w:num) in word/numbering.xml.
    module Numbering
      NS = Package::NS

      # Makes the numbering instance +num+ start level +level+ at +value+,
      # in the override that level may have already.
      def self.start_at(num, level, value)
        override = num.at_xpath("w:lvlOverride[@w:ilvl='#{level}']", NS) ||
                   num.add_child(%(<w:lvlOverride w:ilvl="#{level}"/>)).first
        start = override.at_xpath('w:startOverride', NS) || override.prepend_child('<w:startOverride/>').first
        start['w:val'] = value.to_s
        num
      end
    end
  end
end
