"""Compare actual metrics with frozen, separately recorded regression limits."""
import math
from artifacts import ValidationError


def compare(report, budgets):
    if budgets.get("schemaVersion") != 1 or not budgets.get("metrics"):
        raise ValidationError("missing frozen budgets")
    for field in ("probeSourceSHA256", "manifestSHA256", "nativeCallMaxUTF16"):
        if field in budgets and report.get(field) != budgets[field]:
            raise ValidationError("changed gate identity: " + field)
    actual, expected = report.get("metrics", {}), budgets["metrics"]
    if actual.keys() != expected.keys():
        raise ValidationError("missing metrics or changed metric inventory")
    for name, value in actual.items():
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value <= 0:
            raise ValidationError("invalid metric: " + name)
        row = expected[name]
        limit = row["limit"]
        if row["unit"] not in ("ns", "bytes") or isinstance(limit, bool) \
                or not isinstance(limit, (int, float)) or not math.isfinite(limit) or limit <= 0:
            raise ValidationError("invalid frozen metric: " + name)
        if value > row["limit"]:
            raise ValidationError(f"budget regression: {name} = {value} > {row['limit']}")


def freeze(report):
    return {"schemaVersion": 1, "host": report["host"],
            "probeSourceSHA256": report["probeSourceSHA256"],
            "manifestSHA256": report["manifestSHA256"],
            "nativeCallMaxUTF16": 1024,
            "metrics": {name: {"baselineMaximum": value,
                               "limit": math.ceil(value * (1.10 if name.endswith("Bytes") else 1.25)),
                               "unit": "bytes" if name.endswith("Bytes") else "ns"}
                        for name, value in report["metrics"].items()}}
