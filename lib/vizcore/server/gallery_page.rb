# frozen_string_literal: true

require "cgi"

module Vizcore
  module Server
    # Renders the browser HTML for the bundled example gallery.
    class GalleryPage
      # @param entries [Array<Hash>]
      # @param poster_path [String]
      def initialize(entries:, poster_path:)
        @entries = entries
        @poster_path = poster_path
      end

      # @return [String]
      def render
        cards = @entries.map { |entry| render_card(entry) }.join
        <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Vizcore Example Gallery</title>
            <style>#{css}</style>
          </head>
          <body>
            <main>
              <header class="header">
                <img src="#{@poster_path}" alt="" class="poster">
                <div>
                  <p class="eyebrow">Vizcore Examples</p>
                  <h1>Example Gallery</h1>
                  <p class="lede">Bundled scenes with scene counts, layer counts, audio-source hints, and launch commands.</p>
                </div>
              </header>
              <section class="grid" aria-label="Example scenes">
                #{cards}
              </section>
            </main>
          </body>
          </html>
        HTML
      end

      private

      def render_card(entry)
        scenes = entry.fetch(:scene_names).empty? ? "none" : entry.fetch(:scene_names).join(", ")
        <<~HTML
          <article class="card">
            <div class="thumb"></div>
            <div class="card-body">
              <h2>#{escape(entry.fetch(:title))}</h2>
              <p>#{escape(entry.fetch(:description))}</p>
              <dl>
                <div><dt>File</dt><dd>#{escape(entry.fetch(:file))}</dd></div>
                <div><dt>Scenes</dt><dd>#{escape(scenes)}</dd></div>
                <div><dt>Layers</dt><dd>#{entry.fetch(:layer_count)}</dd></div>
                <div><dt>Audio</dt><dd>#{escape(entry.fetch(:audio_source))}</dd></div>
              </dl>
              <code>#{escape(entry.fetch(:command))}</code>
            </div>
          </article>
        HTML
      end

      def css
        <<~CSS
          :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #090b10; color: #ecf4ff; }
          * { box-sizing: border-box; }
          body { margin: 0; min-height: 100vh; background: #090b10; }
          main { width: min(1180px, calc(100% - 32px)); margin: 0 auto; padding: 32px 0 48px; }
          .header { display: grid; grid-template-columns: minmax(220px, 360px) 1fr; gap: 28px; align-items: end; margin-bottom: 28px; }
          .poster { width: 100%; aspect-ratio: 16 / 9; object-fit: cover; border-radius: 8px; border: 1px solid rgba(255, 255, 255, 0.14); }
          .eyebrow { margin: 0 0 8px; color: #7dd3fc; font-size: 13px; text-transform: uppercase; letter-spacing: 0; }
          h1 { margin: 0; font-size: 42px; line-height: 1.05; letter-spacing: 0; }
          .lede { max-width: 680px; margin: 14px 0 0; color: #b8c7d9; font-size: 17px; line-height: 1.55; }
          .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; }
          .card { overflow: hidden; border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 8px; background: #111722; }
          .thumb { height: 96px; background: url("#{@poster_path}") center / cover; border-bottom: 1px solid rgba(255, 255, 255, 0.1); }
          .card-body { padding: 16px; }
          h2 { margin: 0 0 8px; font-size: 20px; line-height: 1.2; letter-spacing: 0; }
          p { margin: 0 0 14px; color: #bdcadb; line-height: 1.5; }
          dl { display: grid; gap: 8px; margin: 0 0 14px; }
          dl div { display: grid; grid-template-columns: 68px 1fr; gap: 10px; }
          dt { color: #7dd3fc; font-size: 12px; text-transform: uppercase; }
          dd { margin: 0; color: #dfe9f6; overflow-wrap: anywhere; }
          code { display: block; min-height: 52px; padding: 10px; border-radius: 6px; background: #05070b; color: #b8f7d4; overflow-wrap: anywhere; line-height: 1.45; }
          @media (max-width: 720px) { .header { grid-template-columns: 1fr; } h1 { font-size: 34px; } }
        CSS
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
