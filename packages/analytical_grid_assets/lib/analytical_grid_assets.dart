/// The ANALYTICAL domain grid assets — station health and effectiveness
/// REPORTING over the_grid's typed session-ledger metrics projection.
///
/// Domain components: the pure view models ([StationMetricsReport] and
/// friends) and [buildStationMetricsReport], which are pure over the read
/// model so a Flutter cockpit history surface renders them without the CLI.
/// CLI component: [MetricsCommand], the coupled deterministic half a skill
/// calls.
///
/// This pack REPORTS. It presents the projection the_grid landed; it never
/// re-derives it, never renders a live view (the cockpit owns what is running
/// now), and never enforces a budget — enforcement is a later decision, taken
/// after retained metrics exist.
library;

export 'src/metrics/distribution.dart';
export 'src/metrics/ledger_metric.dart';
export 'src/metrics/ledger_source.dart';
export 'src/metrics/metrics_command.dart';
export 'src/metrics/metrics_store.dart';
export 'src/metrics/split_axis.dart';
export 'src/metrics/station_metrics_builder.dart';
export 'src/metrics/station_metrics_render.dart';
export 'src/metrics/station_metrics_report.dart';
export 'src/metrics/station_metrics_service.dart';
export 'src/metrics/work_bucket.dart';
