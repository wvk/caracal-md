require 'nokogiri'
require 'set'
require 'zlib'

module Caracal
  module Md
    # SVG from untrusted sources: recognizes it, cleans it and reads its size.
    #
    # Svg.clean parses without DTD, entities or network, and keeps only an
    # allowlist of SVG elements and attributes. It drops scripts, event
    # handlers, foreignObject, animation, processing instructions and
    # comments, references other than #id and inline PNG/JPEG/GIF data, and
    # CSS that loads anything. It refuses what it can't clean safely: entity
    # declarations, an internal DTD, malformed XML, other root elements,
    # more than max_elements nodes, reference cycles and <use> trees that
    # expand beyond max_expanded nodes.
    module Svg
      class Error < StandardError; end

      # The cleaned markup, its natural size in points, and what was removed.
      Clean = Data.define(:svg, :width, :height, :removed)

      SVG_NS   = 'http://www.w3.org/2000/svg'.freeze
      XLINK_NS = 'http://www.w3.org/1999/xlink'.freeze
      XML_NS   = 'http://www.w3.org/XML/1998/namespace'.freeze

      MAX_BYTES    = 20 * 1024 * 1024
      MAX_ELEMENTS = 100_000
      MAX_EXPANDED = 1_000_000
      MAX_DEPTH    = 500

      ELEMENTS = Set.new(%w[
        svg g defs symbol use switch desc title view a style
        path rect circle ellipse line polyline polygon text tspan textPath image
        clipPath mask pattern marker linearGradient radialGradient stop filter
        feBlend feColorMatrix feComponentTransfer feComposite feConvolveMatrix feDiffuseLighting
        feDisplacementMap feDistantLight feDropShadow feFlood feFuncA feFuncB feFuncG feFuncR
        feGaussianBlur feImage feMerge feMergeNode feMorphology feOffset fePointLight
        feSpecularLighting feSpotLight feTile feTurbulence
      ]).freeze

      # Elements that are nothing without their reference.
      NEEDS_HREF = Set.new(%w[use image feImage textPath]).freeze

      ATTRIBUTES = Set.new(%w[
        id class style lang version baseProfile systemLanguage target type media
        x y x1 y1 x2 y2 cx cy r rx ry fx fy fr width height d points pathLength
        viewBox preserveAspectRatio transform transform-origin
        gradientTransform gradientUnits spreadMethod offset
        patternTransform patternUnits patternContentUnits
        clipPathUnits maskUnits maskContentUnits markerUnits markerWidth markerHeight refX refY orient
        dx dy rotate textLength lengthAdjust startOffset method spacing side
        text-anchor dominant-baseline alignment-baseline baseline-shift
        font-family font-size font-size-adjust font-stretch font-style font-variant font-weight
        letter-spacing word-spacing text-decoration writing-mode direction unicode-bidi
        fill fill-opacity fill-rule stroke stroke-width stroke-opacity stroke-linecap stroke-linejoin
        stroke-miterlimit stroke-dasharray stroke-dashoffset opacity color display visibility overflow
        clip-path clip-rule mask filter marker-start marker-mid marker-end stop-color stop-opacity
        flood-color flood-opacity lighting-color color-interpolation color-interpolation-filters
        color-rendering shape-rendering text-rendering image-rendering paint-order vector-effect
        mix-blend-mode isolation
        filterUnits primitiveUnits in in2 result stdDeviation operator k1 k2 k3 k4 mode values
        tableValues slope intercept amplitude exponent order kernelMatrix divisor bias targetX targetY
        edgeMode kernelUnitLength preserveAlpha surfaceScale diffuseConstant specularConstant
        specularExponent azimuth elevation z pointsAtX pointsAtY pointsAtZ limitingConeAngle scale
        xChannelSelector yChannelSelector radius baseFrequency numOctaves seed stitchTiles
      ]).freeze

      FRAGMENT     = /\A#[^\s#]+\z/
      RASTER_DATA  = %r{\Adata:image/(?:png|jpeg|gif);base64,([A-Za-z0-9+/=\s]+)\z}
      URL_CALL     = /url\s*\(/i
      FRAGMENT_URL = /url\(\s*(['"]?)#[^'"()\s]+\1\s*\)/i
      UNSAFE_CSS   = /[\\\x00-\x08\x0B\x0C\x0E-\x1F]|@import|expression\s*\(|javascript:|behavior\s*:|-moz-binding|image-set\s*\(|src\s*\(/i
      SNIFF        = /\A\s*(?:<\?xml[^>]*\?>\s*)?(?:(?:<!--.*?-->|<!DOCTYPE[^>\[]*(?:\[.*?\])?\s*>)\s*)*<svg[\s>\/]/m
      BOM          = "\xEF\xBB\xBF".b.freeze

      UNITS = { '' => 0.75, 'px' => 0.75, 'pt' => 1.0, 'pc' => 12.0, 'mm' => 72 / 25.4, 'cm' => 72 / 2.54, 'in' => 72.0 }.freeze

      module_function

      # Whether caracal's img takes SVG markup next to the raster image
      # (caracal after 2.0.0).
      def embeddable?
        Caracal::Core::Models::ImageModel.method_defined?(:svg?)
      end

      # A transparent PNG with the proportions of +width+ × +height+: the
      # fallback for readers without SVG support when nothing rasterizes
      # the SVG.
      def blank_png(width, height, longest: 32)
        scale  = longest / [width, height].max.to_f
        pixels = [width, height].map { |side| (side * scale).round.clamp(1, longest) }
        row    = "\0".b * (1 + 2 * pixels[0]) # filter byte, then gray and alpha per pixel
        chunk  = ->(type, data) { [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N') }
        "\x89PNG\r\n\x1a\n".b +
          chunk.call('IHDR'.b, pixels.pack('NN') + [8, 4, 0, 0, 0].pack('C5')) +
          chunk.call('IDAT'.b, Zlib::Deflate.deflate(row * pixels[1])) +
          chunk.call('IEND'.b, ''.b)
      end

      # Whether +bytes+ look like an SVG document.
      def svg?(bytes)
        bytes.is_a?(String) and bytes.b[0, 4096].delete_prefix(BOM).match?(SNIFF)
      end

      def clean(bytes, max_bytes: MAX_BYTES, max_elements: MAX_ELEMENTS, max_expanded: MAX_EXPANDED)
        raise Error, "larger than #{max_bytes} bytes" if bytes.bytesize > max_bytes

        text = bytes.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
        raise Error, 'not UTF-8' unless text.valid_encoding?
        raise Error, 'declares entities or an internal DTD' if text.match?(/<!ENTITY|<!DOCTYPE[^>\[]*\[/i)

        root = parse(text).root
        raise Error, 'has no svg root element' unless root and root.name == 'svg' and root.namespace&.href == SVG_NS
        raise Error, "has more than #{max_elements} nodes" if root.xpath('descendant-or-self::node()').size > max_elements

        removed = Set.new
        scrub_attributes(root, removed)
        scrub(root, removed, 0)
        check_references(root, max_expanded)

        width, height = size(root)
        Clean.new(svg: %(<?xml version="1.0" encoding="UTF-8"?>\n#{root.to_xml}), width: width, height: height, removed: removed.to_a.sort)
      end

      # The natural size in points: width and height, or the viewBox in
      # pixels, or the 300 × 150 pixels browsers use.
      def size(root)
        width  = length(root['width'])
        height = length(root['height'])
        box    = root['viewBox'].to_s.split(/[\s,]+/).map(&:to_f)
        box_w, box_h = (box[2, 2] if box.size == 4 and box[2].positive? and box[3].positive?)

        if width and height then [width, height]
        elsif width and box_w then [width, width * box_h / box_w]
        elsif height and box_w then [height * box_w / box_h, height]
        elsif box_w then [box_w * 0.75, box_h * 0.75]
        else [225.0, 112.5]
        end
      end

      def length(value)
        match = value.to_s.strip.match(/\A(\d+(?:\.\d+)?|\.\d+)\s*(px|pt|pc|mm|cm|in)?\z/)
        return unless match

        number = match[1].to_f
        number * UNITS.fetch(match[2].to_s) if number.positive?
      end

      def parse(text)
        options = Nokogiri::XML::ParseOptions::STRICT | Nokogiri::XML::ParseOptions::NONET
        Nokogiri::XML(text, nil, 'UTF-8', options)
      rescue Nokogiri::XML::SyntaxError => e
        raise Error, "is no well-formed XML (#{e.message.strip})"
      end

      def scrub(node, removed, depth)
        raise Error, "nests deeper than #{MAX_DEPTH} levels" if depth > MAX_DEPTH

        node.children.each do |child|
          if child.element?
            scrub_element(child, removed, depth)
          elsif not (child.text? or child.cdata?)
            child.remove # comments, processing instructions, entity references
          end
        end
      end

      def scrub_element(el, removed, depth)
        svg = el.namespace&.href == SVG_NS
        unless svg and ELEMENTS.include?(el.name)
          removed << el.name if svg # other namespaces hold editor data
          return el.remove
        end
        if el.name == 'style' and not css_safe?(el.content)
          removed << 'style element loading resources'
          return el.remove
        end

        scrub_attributes(el, removed)
        return el.remove if NEEDS_HREF.include?(el.name) and href(el).nil?

        scrub(el, removed, depth + 1)
      end

      def scrub_attributes(el, removed)
        el.attribute_nodes.each do |attr|
          keep = case attr.namespace&.href
                 when nil      then attribute_ok?(el, attr, removed)
                 when XLINK_NS then attr.name == 'href' ? href_ok?(attr.value, removed) : attr.name == 'title'
                 when XML_NS   then %w[space lang].include?(attr.name)
                 else false
                 end
          attr.remove unless keep
        end
      end

      def attribute_ok?(el, attr, removed)
        name = attr.name
        if name.match?(/\Aon/i)
          removed << name
          false
        elsif name == 'href'
          href_ok?(attr.value, removed)
        elsif name == 'style'
          declarations = attr.value.split(';')
          safe = declarations.select { |declaration| css_safe?(declaration) }
          removed << 'style declarations loading resources' if safe.size < declarations.size
          attr.value = safe.join(';')
          not safe.empty?
        elsif not ATTRIBUTES.include?(name)
          removed << name
          false
        elsif css_safe?(attr.value)
          true
        else
          removed << "#{name} loading resources"
          false
        end
      end

      # #id references and inline PNG, JPEG or GIF data stay.
      def href_ok?(value, removed)
        value = value.strip
        return true if value.match?(FRAGMENT)

        data = value[RASTER_DATA, 1]
        return true if data and Caracal::ImageSize.read(data.unpack1('m'))

        removed << 'external references'
        false
      end

      def href(el)
        el.attribute_with_ns('href', XLINK_NS)&.value || el['href']
      end

      def css_safe?(css)
        not css.match?(UNSAFE_CSS) and css.scan(URL_CALL).size == css.scan(FRAGMENT_URL).size
      end

      # Refuses reference cycles and trees that expand beyond +limit+ nodes
      # once every #id reference is followed.
      def check_references(root, limit)
        ids = {}
        root.xpath('descendant-or-self::*[@id]').each { |el| ids[el['id']] ||= el }
        sizes = {}.compare_by_identity
        visiting = {}.compare_by_identity
        expand = lambda do |el, depth|
          return sizes[el] if sizes.key?(el)
          raise Error, 'has a reference cycle' if visiting[el]
          raise Error, "nests deeper than #{MAX_DEPTH} levels" if depth > MAX_DEPTH

          visiting[el] = true
          total  = 1 + el.element_children.sum { |child| expand.call(child, depth + 1) }
          reference = href(el).to_s
          target = (ids[reference[1..]] if reference.start_with?('#') and el.name != 'a')
          total += expand.call(target, depth + 1) if target
          raise Error, "expands to more than #{limit} nodes" if total > limit

          visiting.delete(el)
          sizes[el] = total
        end
        expand.call(root, 0)
      end
    end
  end
end
