// SPK-15's benchmarks, one module a lever (the package's `src/lib.cairo` names them). Every figure
// of the report is the difference of snforge's totals of two tests that differ by the measured call
// alone: `*_base` (or `*_fixture`) against its pair.
mod bench_application;
mod bench_design;
mod bench_executor;
mod bench_perception;
mod bench_words;
mod fixtures;
