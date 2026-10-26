# Native template service marks

Added 02-Oct-2026. The UI uses these monochrome vector PDFs instead of status-page favicons. Unused status-page favicons are excluded from this distribution.

Vector paths come from Simple Icons 15.4.0, commit `714bb7a096ccc35cc2b7137657a4d2ccdfcd1206`. Each retained `*-template.svg` is the unmodified upstream source; each `*-template.pdf` is its vector-only PDF conversion with transparent background and a normalized 24-point square envelope. Tight silhouette bounds are centered; aspect ratios are preserved. The view renders all marks with the same 10% optical inset and native template tint.

| Service | Pinned vector source |
| --- | --- |
| OpenAI | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/openai.svg |
| Claude | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/claude.svg |
| GitHub | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/github.svg |
| Cloudflare | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/cloudflare.svg |
| Supabase | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/supabase.svg |
| Vercel | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/vercel.svg |
| Stripe | https://raw.githubusercontent.com/simple-icons/simple-icons/714bb7a096ccc35cc2b7137657a4d2ccdfcd1206/icons/stripe.svg |

Simple Icons provides these assets under CC0; the exact upstream license is retained in `SIMPLE_ICONS_LICENSE.md`. Brand and trademark rights remain with the respective owners. These are recognizable service marks, not claims of provider affiliation or Apple-issued brand icons.

Conversion used svglib 2.2.0 and ReportLab 5.0.1 in a temporary `uv run` environment, without adding app/runtime dependencies. All seven normalized bounds were checked to lie within the 24×24-point canvas. macOS sips successfully decoded OpenAI and Cloudflare PDF previews. Full app rendering and light/dark validation are performed by the integrating owner.
