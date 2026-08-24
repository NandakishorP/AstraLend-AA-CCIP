/**
 * The shared page backdrop: an aurora field over a faint grid.
 *
 * Rendered once per layout and pinned behind everything. Pure CSS — no canvas,
 * no images — so it costs nothing on first paint and scales to any viewport.
 */
export function Backdrop({ intensity = "full" }: { intensity?: "full" | "subtle" }) {
  const opacity = intensity === "full" ? "opacity-100" : "opacity-40";

  return (
    <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden" aria-hidden>
      <div className="absolute inset-0 bg-void" />

      <div className={`absolute inset-0 ${opacity}`}>
        <div
          className="absolute -left-[15%] -top-[25%] size-[46rem] animate-aurora rounded-full blur-[120px]"
          style={{
            background:
              "radial-gradient(circle at 40% 40%, rgba(124,58,237,0.55), rgba(124,58,237,0) 65%)",
          }}
        />
        <div
          className="absolute -right-[10%] top-[8%] size-[38rem] animate-aurora rounded-full blur-[110px] [animation-delay:-6s]"
          style={{
            background:
              "radial-gradient(circle at 50% 50%, rgba(34,211,238,0.34), rgba(34,211,238,0) 65%)",
          }}
        />
        <div
          className="absolute bottom-[-20%] left-[25%] size-[40rem] animate-aurora rounded-full blur-[130px] [animation-delay:-12s]"
          style={{
            background:
              "radial-gradient(circle at 50% 50%, rgba(56,189,248,0.22), rgba(14,165,233,0) 70%)",
          }}
        />
      </div>

      <div className="grid-lines absolute inset-0 opacity-[0.35] [mask-image:radial-gradient(ellipse_at_50%_0%,black,transparent_75%)]" />

      {/* Vignette keeps the page edges dark so content holds the centre. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_-10%,transparent_35%,rgba(5,6,12,0.85)_100%)]" />
    </div>
  );
}
