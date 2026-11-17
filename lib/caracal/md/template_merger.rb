module Caracal
  module Md
    # Puts the body of a caracal-generated package into a copy of a Word
    # template, keeping the template's styles, theme, fonts, settings,
    # numbering, headers, footers and page setup.
    #
    # Styles are matched by name, so a German template's "berschrift1" (named
    # "heading 1") takes the place of caracal's "Heading1". Styles the template
    # lacks are copied over from the generated package.
    class TemplateMerger
      NS = Package::NS
      W  = NS['w']

      MACRO_TYPES = %w[
        application/vnd.ms-word.document.macroEnabled.main+xml
        application/vnd.ms-word.template.macroEnabledTemplate.main+xml
        application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml
      ].freeze

      attr_reader :warnings

      # style_map: style ids of Styles (or their names) => template style ids or names.
      # placeholder: a paragraph with this text receives the content; without
      # one, the content replaces the template's body.
      def initialize(template, generated, style_map: {}, placeholder: '{{content}}', variables: {})
        @template    = Template.load(template)
        @generated   = generated
        @style_map   = style_map.to_h.transform_keys(&:to_s).transform_values(&:to_s)
        @placeholder = placeholder
        @variables   = variables
        @warnings    = []
      end

      def merge
        @out      = @template.package.dup
        @out_main = @out.main_part
        @gen_main = @generated.main_part
        @gen_doc  = @generated.xml(@gen_main)
        @gen_body = @gen_doc.at_xpath('/w:document/w:body', NS)

        make_document
        rewrite_styles merge_styles
        num_map = merge_numbering
        rewrite_numbering num_map
        number_lists num_map
        rewrite_relationships merge_relationships
        offset_ids
        insert_body
        merge_settings
        replace_placeholders
        @out
      end

      private

      #========== PACKAGE =====================================

      # A template or macro-enabled main part becomes a plain document part.
      def make_document
        if MACRO_TYPES.include?(@out.override_content_type(@out_main))
          @out.set_override(@out_main, Package::CONTENT_TYPES[:document])
        end

        @out.relationships(@out_main).select { |r| r[:type] == Package::REL_TYPES[:vba_project] }.each do |rel|
          part = @out.resolve(@out_main, rel[:target])
          [part, @out.rels_name(part), part.sub(/vbaProject\.bin\z/, 'vbaData.xml')].each do |name|
            @out.delete(name)
            @out.remove_override(name)
          end
          @out.remove_relationship(@out_main, rel[:id])
        end
      end

      #========== STYLES ======================================

      # Returns generated style id => output style id.
      def merge_styles
        gen_part = @generated.related_part(@gen_main, :styles) or return {}
        out_part = @out.related_part(@out_main, :styles)
        unless out_part
          out_part = 'word/styles.xml'
          @out[out_part] = @generated[gen_part]
          @out.add_relationship(@out_main, Package::REL_TYPES[:styles], 'styles.xml')
          @out.set_override(out_part, @generated.override_content_type(gen_part))
          return {}
        end

        @gen_styles = index_styles(@generated.xml(gen_part))
        @out_doc    = @out.xml(out_part)
        @out_styles = index_styles(@out_doc)
        @mapping    = {}

        used = @gen_body.xpath('.//w:pStyle/@w:val | .//w:rStyle/@w:val | .//w:tblStyle/@w:val', NS).map(&:value).uniq
        used.each { |id| resolve_style(id) }
        @mapping
      end

      def index_styles(doc)
        ids   = {}
        names = {}
        doc.xpath('/w:styles/w:style', NS).each do |style|
          id   = style['w:styleId']
          name = style.at_xpath('w:name/@w:val', NS)&.value
          ids[id] = style
          names[name.downcase] ||= id if name
        end
        { ids: ids, names: names }
      end

      def resolve_style(id)
        return @mapping[id] if @mapping.key?(id)

        node = @gen_styles[:ids][id]
        name = node&.at_xpath('w:name/@w:val', NS)&.value
        @mapping[id] = mapped_style(id, name) || template_style(name) || (id if @out_styles[:ids][id] and not node)
        @mapping[id] ||= node ? import_style(id, node) : id
      end

      def mapped_style(id, name)
        wanted = @style_map[id] || (name and @style_map.find { |k, _| k.casecmp?(name) }&.last)
        return unless wanted

        found = (wanted if @out_styles[:ids][wanted]) || @out_styles[:names][wanted.downcase]
        @warnings << "style_map: the template has no style #{wanted.inspect}" unless found
        found
      end

      def template_style(name)
        name && @out_styles[:names][name.downcase]
      end

      def import_style(id, node)
        new_id = id
        new_id = "#{new_id}Md" while @out_styles[:ids][new_id]
        @mapping[id] = new_id

        copy = node.dup
        copy['w:styleId'] = new_id
        copy.xpath('w:basedOn | w:next | w:link', NS).each do |ref|
          target = resolve_style(ref['w:val'])
          target ? ref['w:val'] = target : ref.remove
        end
        imported = @out_doc.root.add_child(@out_doc.root.parse(copy.to_xml)).first
        @out_styles[:ids][new_id] = imported
        name = copy.at_xpath('w:name/@w:val', NS)&.value
        @out_styles[:names][name.downcase] ||= new_id if name
        new_id
      end

      def rewrite_styles(mapping)
        @gen_body.xpath('.//w:pStyle | .//w:rStyle | .//w:tblStyle', NS).each do |node|
          node['w:val'] = mapping[node['w:val']] if mapping[node['w:val']]
        end
      end

      #========== NUMBERING ===================================

      # Copies the generated lists' numbering; returns generated numId => output numId.
      def merge_numbering
        gen_part = @generated.related_part(@gen_main, :numbering) or return {}
        gen_doc  = @generated.xml(gen_part)
        abstracts = gen_doc.xpath('/w:numbering/w:abstractNum', NS)
        nums      = gen_doc.xpath('/w:numbering/w:num', NS)
        return {} if nums.empty?

        out_part = @out.related_part(@out_main, :numbering)
        unless out_part
          out_part = 'word/numbering.xml'
          @out[out_part] = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:numbering xmlns:w="#{W}"/>)
          @out.add_relationship(@out_main, Package::REL_TYPES[:numbering], 'numbering.xml')
          @out.set_override(out_part, Package::CONTENT_TYPES[:numbering])
        end
        out_doc = @out.xml(out_part)

        next_abstract = out_doc.xpath('//w:abstractNum/@w:abstractNumId', NS).map { |a| a.value.to_i }.max.to_i + 1
        next_num      = out_doc.xpath('//w:num/@w:numId', NS).map { |a| a.value.to_i }.max.to_i + 1
        abstract_map  = {}
        num_map       = {}

        abstract_xml = abstracts.map do |abstract|
          copy = abstract.dup
          abstract_map[copy['w:abstractNumId']] = next_abstract.to_s
          copy['w:abstractNumId'] = next_abstract.to_s
          next_abstract += 1
          copy.xpath('.//w:pStyle', NS).each { |s| s['w:val'] = @mapping[s['w:val']] if @mapping&.dig(s['w:val']) }
          copy.to_xml
        end.join

        num_xml = nums.map do |num|
          copy = num.dup
          num_map[copy['w:numId']] = next_num.to_s
          copy['w:numId'] = next_num.to_s
          next_num += 1
          ref = copy.at_xpath('w:abstractNumId', NS)
          ref['w:val'] = abstract_map.fetch(ref['w:val'], ref['w:val'])
          copy.to_xml
        end.join

        root = out_doc.root
        first_num = root.at_xpath('w:num', NS)
        cleanup   = root.at_xpath('w:numIdMacAtCleanup', NS)
        new_abstracts = root.parse(abstract_xml)
        first_num ? first_num.add_previous_sibling(new_abstracts) : (cleanup ? cleanup.add_previous_sibling(new_abstracts) : root.add_child(new_abstracts))
        new_nums = root.parse(num_xml)
        cleanup ? cleanup.add_previous_sibling(new_nums) : root.add_child(new_nums)
        num_map
      end

      def rewrite_numbering(mapping)
        @gen_body.xpath('.//w:numId', NS).each do |node|
          node['w:val'] = mapping[node['w:val']] if mapping[node['w:val']]
        end
      end

      #========== LISTS =======================================

      # Elements a paragraph's w:numPr follows in w:pPr.
      BEFORE_NUM_PR = %w[pStyle keepNext keepLines pageBreakBefore framePr widowControl].freeze

      # List items whose style carries numbering in the template (List
      # Bullet, List Number 2, …) take the style's bullets, numbers and
      # indentation instead of caracal's. Every numbered list gets its own
      # numbering instance, so it starts at 1 whichever numbering it uses.
      # Text after a nested list keeps its item's style without the number.
      # Copies of caracal's numbering no item uses any more are removed.
      def number_lists(num_map)
        return if num_map.empty?

        @numbering        = @out.xml(@out.related_part(@out_main, :numbering))
        @style_numberings = {}
        instances         = {} # caracal numId => { level => numbering instance }

        @gen_body.xpath('.//w:p/w:pPr', NS).each do |ppr|
          style  = ppr.at_xpath('w:pStyle/@w:val', NS)&.value
          list   = style && style_numbering(style)
          num_pr = ppr.at_xpath('w:numPr', NS)
          if num_pr
            number_list_item(ppr, num_pr, list, instances)
          elsif list and (ind = ppr.at_xpath('w:ind', NS))
            continue_list_item(ppr, ind, list)
          end
        end
        prune_numbering(num_map.values)
      end

      def number_list_item(ppr, num_pr, list, instances)
        num_id  = num_pr.at_xpath('w:numId/@w:val', NS)&.value
        caracal = numbering_level(num_id, num_pr.at_xpath('w:ilvl/@w:val', NS)&.value || '0') or return
        open    = instances[num_id] ||= {}
        level   = caracal[:ilvl].to_i
        open.reject! { |l, _| l > level }

        if list
          ppr.xpath('w:ind | w:contextualSpacing', NS).each(&:remove)
          return num_pr.remove if list[:bullet]
        else
          return if caracal[:bullet]

          list = caracal
        end

        num_id = open[level] ||= add_numbering_instance(list)
        num_pr.children.remove
        num_pr.add_child(%(<w:ilvl w:val="#{list[:ilvl]}"/><w:numId w:val="#{num_id}"/>))
      end

      # A paragraph after a nested list, indented to the item's text.
      def continue_list_item(ppr, ind, list)
        ppr.at_xpath('w:contextualSpacing', NS)&.remove
        before = ppr.element_children.reverse.find { |el| BEFORE_NUM_PR.include?(el.name) }
        num_pr = '<w:numPr><w:numId w:val="0"/></w:numPr>'
        before ? before.add_next_sibling(num_pr) : ppr.prepend_child(num_pr)

        text  = list[:lvl].at_xpath('w:pPr/w:ind', NS)
        start = text && (text['w:start'] || text['w:left'])
        ind['w:start'] = start if start
      end

      # The numbering a template style carries, itself or through the
      # styles it is based on, or nil.
      def style_numbering(id)
        return @style_numberings[id] if @style_numberings.key?(id)
        return unless @out_styles

        num_id = ilvl = nil
        seen   = []
        style  = @out_styles[:ids][id]
        while style and not seen.include?(style)
          seen << style
          if (num_pr = style.at_xpath('w:pPr/w:numPr', NS))
            ilvl   ||= num_pr.at_xpath('w:ilvl/@w:val', NS)&.value
            num_id ||= num_pr.at_xpath('w:numId/@w:val', NS)&.value
            break if num_id
          end
          style = @out_styles[:ids][style.at_xpath('w:basedOn/@w:val', NS)&.value]
        end
        return @style_numberings[id] = nil if num_id.nil? or num_id == '0'

        # A level that names the style takes precedence over the style's ilvl.
        linked = abstract_numbering(num_id)&.at_xpath("w:lvl[w:pStyle/@w:val='#{id}']/@w:ilvl", NS)&.value
        @style_numberings[id] = numbering_level(num_id, linked || ilvl || '0')
      end

      # { num:, ilvl:, lvl:, bullet: } for level +ilvl+ of numbering
      # instance +num_id+, or nil when the numbering lacks it.
      def numbering_level(num_id, ilvl)
        num      = numbering_instance(num_id) or return
        abstract = abstract_numbering(num_id) or return
        lvl      = num.at_xpath("w:lvlOverride[@w:ilvl='#{ilvl}']/w:lvl", NS) ||
                   abstract.at_xpath("w:lvl[@w:ilvl='#{ilvl}']", NS) or return
        { num: num_id, ilvl: ilvl, lvl: lvl, bullet: %w[bullet none].include?(lvl.at_xpath('w:numFmt/@w:val', NS)&.value) }
      end

      def numbering_instance(num_id)
        @numbering.at_xpath("/w:numbering/w:num[@w:numId='#{num_id}']", NS)
      end

      # The abstract numbering of an instance, following a numbering style
      # link (w:numStyleLink) to the definition with the levels.
      def abstract_numbering(num_id, depth = 0)
        abstract_id = numbering_instance(num_id)&.at_xpath('w:abstractNumId/@w:val', NS)&.value or return
        abstract = @numbering.at_xpath("/w:numbering/w:abstractNum[@w:abstractNumId='#{abstract_id}']", NS) or return
        link = abstract.at_xpath('w:numStyleLink/@w:val', NS)&.value
        return abstract unless link and depth < 2

        linked = @out_styles && @out_styles[:ids][link]&.at_xpath('w:pPr/w:numPr/w:numId/@w:val', NS)&.value
        linked ? abstract_numbering(linked, depth + 1) : abstract
      end

      # A copy of the list's numbering instance that starts the list's
      # level at 1; returns its numId.
      def add_numbering_instance(list)
        copy = numbering_instance(list[:num]).dup
        copy['w:numId'] = (@numbering.xpath('/w:numbering/w:num/@w:numId', NS).map { |a| a.value.to_i }.max.to_i + 1).to_s
        Numbering.start_at(copy, list[:ilvl], 1)
        @numbering.xpath('/w:numbering/w:num', NS).last.add_next_sibling(copy)
        copy['w:numId']
      end

      def prune_numbering(num_ids)
        used = @gen_body.xpath('.//w:numId/@w:val', NS).map(&:value)
        (num_ids - used).each do |num_id|
          num = numbering_instance(num_id) or next
          abstract_id = num.at_xpath('w:abstractNumId/@w:val', NS)&.value
          num.remove
          next if @numbering.at_xpath("/w:numbering/w:num[w:abstractNumId/@w:val='#{abstract_id}']", NS)

          @numbering.at_xpath("/w:numbering/w:abstractNum[@w:abstractNumId='#{abstract_id}']", NS)&.remove
        end
      end

      #========== RELATIONSHIPS ===============================

      # Copies the relationships the body uses (hyperlinks, images) and their
      # media; returns generated id => output id.
      def merge_relationships
        used = @gen_body.xpath('.//@r:id | .//@r:embed | .//@r:link', NS).map(&:value).uniq
        used.each_with_object({}) do |id, map|
          rel = @generated.relationship(@gen_main, id) or next
          if rel[:mode] == 'External'
            map[id] = @out.add_relationship(@out_main, rel[:type], rel[:target], mode: 'External')
          else
            map[id] = @out.add_relationship(@out_main, rel[:type], copy_part(@generated.resolve(@gen_main, rel[:target])))
          end
        end
      end

      # Copies a part (e.g. an image) into the output; returns its target
      # relative to the output's main part.
      def copy_part(path)
        data = @generated[path]
        name = path
        name = name.sub(/(\.\w+)?\z/) { "-md#{Regexp.last_match(1)}" } while @out.include?(name) and @out[name] != data
        @out[name] = data

        extension = File.extname(name).delete_prefix('.')
        if (type = @generated.override_content_type(path))
          @out.set_override(name, type)
        elsif (type = @generated.default_content_type(extension))
          @out.ensure_default(extension, type)
        end

        dir = File.dirname(@out_main)
        name.start_with?("#{dir}/") ? name.delete_prefix("#{dir}/") : "/#{name}"
      end

      def rewrite_relationships(mapping)
        @gen_body.xpath('.//@r:id | .//@r:embed | .//@r:link', NS).each do |attr|
          attr.value = mapping[attr.value] if mapping[attr.value]
        end
      end

      #========== BODY ========================================

      # Bookmark and drawing ids must stay unique next to the template's.
      def offset_ids
        out_doc = @out.xml(@out_main)
        bookmark_offset = out_doc.xpath('//w:bookmarkStart/@w:id', NS).map { |a| a.value.to_i }.max.to_i
        drawing_offset  = @template.text_parts.flat_map do |part|
          @out.xml(part).xpath('//wp:docPr/@id', NS).map { |a| a.value.to_i }
        end.max.to_i

        @gen_body.xpath('.//w:bookmarkStart | .//w:bookmarkEnd', NS).each do |node|
          node['w:id'] = (node['w:id'].to_i + bookmark_offset).to_s
        end
        @gen_body.xpath('.//wp:docPr', NS).each { |node| node['id'] = (node['id'].to_i + drawing_offset).to_s }
      end

      def insert_body
        out_doc  = @out.xml(@out_main)
        out_root = out_doc.root
        @gen_doc.root.namespace_definitions.each do |ns|
          next if ns.prefix.nil? or out_root.namespace_definitions.any? { |d| d.prefix == ns.prefix }

          out_root.add_namespace_definition(ns.prefix, ns.href)
        end

        content = @gen_body.element_children.reject { |el| el.name == 'sectPr' and el.namespace&.href == W }
        xml     = content.map(&:to_xml).join
        body    = out_doc.at_xpath('/w:document/w:body', NS)
        anchor  = @placeholder && Placeholders.find_paragraph(out_doc, @placeholder)

        if anchor
          parent = anchor.parent
          anchor.add_previous_sibling(parent.parse(xml))
          anchor.remove
          if parent.name == 'tc' and parent.element_children.last&.name != 'p'
            parent.add_child('<w:p/>')
          end
        else
          section = body.at_xpath('w:sectPr', NS)
          body.children.each { |node| node.remove unless node.equal?(section) }
          nodes = body.parse(xml)
          section ? section.add_previous_sibling(nodes) : body.add_child(nodes)
        end
      end

      #========== SETTINGS, PLACEHOLDERS ======================

      def merge_settings
        gen_part = @generated.related_part(@gen_main, :settings) or return
        out_part = @out.related_part(@out_main, :settings) or return
        update = @generated.xml(gen_part).at_xpath('//w:updateFields', NS)
        Settings.ensure(@out.xml(out_part), 'updateFields', '<w:updateFields w:val="true"/>') if update
      end

      def replace_placeholders
        @template.text_parts.each do |part|
          Placeholders.replace(@out.xml(part), @variables)
        end
      end
    end
  end
end
