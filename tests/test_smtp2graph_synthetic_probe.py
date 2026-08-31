#!/usr/bin/env python3
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).parents[1] / "scripts" / "smtp2graph-synthetic-probe.py"
SPEC = importlib.util.spec_from_file_location("smtp2graph_synthetic_probe", MODULE_PATH)
probe = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = probe
SPEC.loader.exec_module(probe)


class SyntheticProbeTest(unittest.TestCase):
    def env(self, directory: str) -> dict[str, str]:
        return {
            "SMTP2GRAPH_SYNTHETIC_HOST": "127.0.0.1",
            "SMTP2GRAPH_SYNTHETIC_PORT": "2525",
            "SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME": "smtp-int.example.test",
            "SMTP2GRAPH_SYNTHETIC_USER": "synthetic",
            "SMTP2GRAPH_SYNTHETIC_PASSWORD": "not-a-real-secret",
            "SMTP2GRAPH_SYNTHETIC_SENDER": "noreply@example.test",
            "SMTP2GRAPH_SYNTHETIC_RECIPIENT": "recipient@example.test",
            "VM_SYNTHETIC_QUERY_URL": "http://127.0.0.1:8428",
            "NODE_EXPORTER_TEXTFILE_DIR": directory,
            "SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS": "5",
        }

    def test_success_requires_delivery_counter_increment(self):
        with tempfile.TemporaryDirectory() as directory:
            config = probe.config_from_env(self.env(directory))
            with patch.object(probe, "query_delivery_count", side_effect=[10.0, 11.0]), patch.object(probe, "submit_message"):
                self.assertTrue(probe.run(config))

    def test_counter_without_increment_is_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            config = probe.config_from_env(self.env(directory))
            with patch.object(probe, "query_delivery_count", return_value=10.0), patch.object(probe, "submit_message"), patch.object(probe.time, "monotonic", side_effect=[0, 10]):
                self.assertFalse(probe.run(config))

    def test_metrics_are_atomic_and_do_not_include_secret_values(self):
        with tempfile.TemporaryDirectory() as directory:
            config = probe.config_from_env(self.env(directory))
            probe.write_metrics(config, 0, 0, 123)
            metrics_path = Path(directory) / "smtp2graph_synthetic.prom"
            metrics = metrics_path.read_text(encoding="utf-8")
            self.assertIn("smtp2graph_synthetic_last_status", metrics)
            self.assertNotIn(config.password, metrics)
            self.assertEqual(metrics_path.stat().st_mode & 0o777, 0o644)

    def test_invalid_port_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            env = self.env(directory)
            env["SMTP2GRAPH_SYNTHETIC_PORT"] = "70000"
            with self.assertRaises(ValueError):
                probe.config_from_env(env)

    def test_tls_hostname_is_independent_from_tcp_endpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            config = probe.config_from_env(self.env(directory))
            self.assertEqual(config.host, "127.0.0.1")
            self.assertEqual(config.tls_server_name, "smtp-int.example.test")


if __name__ == "__main__":
    unittest.main()
