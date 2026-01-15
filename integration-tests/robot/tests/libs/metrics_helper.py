"""Helper function for parsing Prometheus metrics in Robot Framework tests."""

def get_metric_sum(metrics_text, metric_name):
    """
    Extract and sum all values for a given metric name from Prometheus metrics text.
    
    Args:
        metrics_text: The full Prometheus metrics text (string)
        metric_name: The metric name to extract (e.g., 'otelcol_receiver_accepted_spans_total')
    
    Returns:
        float: Sum of all matching metric values, or 0.0 if no matches found
    """
    if not metrics_text or not metric_name:
        return 0.0
    
    total = 0.0
    for line in metrics_text.split('\n'):
        line = line.strip()
        # Skip empty lines and comment lines
        if not line or line.startswith('#'):
            continue
        # Check if line starts with the metric name
        if line.startswith(metric_name):
            try:
                # Extract the last field (the value) - handles labels correctly
                parts = line.split()
                if len(parts) >= 2:
                    value_str = parts[-1]  # Last field is the value
                    total += float(value_str)
            except (ValueError, IndexError):
                # Skip lines that can't be parsed
                continue
    
    return total


