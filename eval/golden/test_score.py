"""score.py is the ruler every detector is measured with (#52), so its counting is pinned here case by case."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import score

HASH = "sha256:" + "0" * 64


def template(cuts: list[int], content_hash: str = HASH) -> dict:
    return {
        "source": {"content_hash": content_hash},
        "tracks": [
            {"id": "video-1", "kind": "video", "cuts": [{"frame": f} for f in cuts]}
        ],
    }


@pytest.mark.parametrize(
    ("pred", "truth", "tol", "matches"),
    [
        ([10, 20], [10, 20], 0, 2),  # exact
        ([12, 22], [10, 20], 2, 2),  # at the edge of the tolerance
        ([13], [10], 2, 0),  # just outside
        ([10, 11], [10], 2, 1),  # two predictions can't share one label
        ([10], [10, 11], 2, 1),  # one prediction can't match two labels
        ([12, 14], [10, 12], 2, 2),  # closest-first pairing would find only 1
        ([], [10], 2, 0),
        ([10], [], 2, 0),
        ([30, 10, 20], [21, 9, 31], 1, 3),  # order doesn't matter
    ],
)
def test_match_count(pred: list[int], truth: list[int], tol: int, matches: int) -> None:
    assert score.match_count(pred, truth, tol) == matches


def test_match_count_is_maximal_on_random_cases() -> None:
    """Against brute force over every one-to-one pairing, on small random inputs."""
    import itertools
    import random

    rng = random.Random(4)
    for _ in range(300):
        pred = rng.sample(range(40), rng.randint(0, 5))
        truth = rng.sample(range(40), rng.randint(0, 5))
        tol = rng.randint(0, 3)
        best = 0
        for k in range(min(len(pred), len(truth)), 0, -1):
            if any(
                all(abs(p - t) <= tol for p, t in zip(ps, ts, strict=True))
                for ps in itertools.permutations(pred, k)
                for ts in itertools.combinations(sorted(truth), k)
            ):
                best = k
                break
        assert score.match_count(pred, truth, tol) == best, (pred, truth, tol)


def test_counts_and_rates() -> None:
    c = score.score_cuts(template([10, 50, 90]), template([10, 50, 70, 80]), [], 2)
    assert (c.true_positives, c.false_positives, c.false_negatives) == (2, 1, 2)
    assert c.precision == pytest.approx(2 / 3) and c.recall == pytest.approx(0.5)
    assert c.f1 == pytest.approx(2 * (2 / 3) * 0.5 / (2 / 3 + 0.5))


def test_no_predictions_or_no_labels_score_zero_not_crash() -> None:
    assert score.score_cuts(template([]), template([10]), [], 2).recall == 0.0
    nothing = score.score_cuts(template([]), template([]), [], 2)
    assert (nothing.precision, nothing.recall, nothing.f1) == (0.0, 0.0, 0.0)


def test_excluded_frames_are_dropped_on_both_sides() -> None:
    # Range 100-119 (half-open, like every schema range): frames 100 and 119 are inside, 120 is not.
    end_card = [{"start": 100, "duration": 20, "reason": "platform end card"}]
    c = score.score_cuts(
        template([50, 100, 119, 120]), template([50, 105, 121]), end_card, 2
    )
    assert (c.true_positives, c.false_positives, c.false_negatives) == (2, 0, 0)


@pytest.fixture
def golden(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    (tmp_path / "labels").mkdir()
    (tmp_path / "labels" / "v01.json").write_text(json.dumps(template([10, 50])))
    (tmp_path / "labels" / "v02.json").write_text(json.dumps(template([30])))
    (tmp_path / "labels" / "v03.json").write_text(json.dumps(template([])))
    videos = [
        {
            "id": "v01",
            "frames": 100,
            "labeled": True,
            "exclude": [{"start": 90, "duration": 10, "reason": "platform end card"}],
        },
        {"id": "v02", "frames": 100, "labeled": True},
        # Ingested but not labeled yet: ingest.py writes an empty label file and labeled: false.
        {"id": "v03", "frames": 100, "labeled": False},
    ]
    (tmp_path / "manifest.json").write_text(json.dumps({"videos": videos}))
    monkeypatch.setattr(score, "ROOT", tmp_path)
    preds = tmp_path / "preds"
    preds.mkdir()
    return preds


def run(monkeypatch: pytest.MonkeyPatch, *args: str) -> None:
    monkeypatch.setattr(sys, "argv", ["score.py", *args])
    score.main()


def test_cli_totals_and_missing_videos(
    golden: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (golden / "v01.json").write_text(
        json.dumps(template([11, 50, 95]))
    )  # 95 is in the end card
    run(monkeypatch, str(golden), "--json")
    out = json.loads(capsys.readouterr().out)
    assert out["missing"] == ["v02"]
    assert out["unlabeled"] == ["v03"]
    assert out["total"]["true_positives"] == 2 and out["total"]["false_positives"] == 0
    assert out["tolerance"] == score.DEFAULT_TOLERANCE

    run(monkeypatch, str(golden), "--tolerance", "0")
    text = capsys.readouterr().out
    assert "±0 frames" in text and "no prediction: v02" in text


def test_cli_refuses_a_prediction_from_another_video(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (golden / "v01.json").write_text(
        json.dumps(template([10], content_hash="sha256:" + "1" * 64))
    )
    with pytest.raises(SystemExit, match="different video"):
        run(monkeypatch, str(golden))


def test_cli_with_no_predictions_stops(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with pytest.raises(SystemExit, match="no predictions"):
        run(monkeypatch, str(golden))


def test_unlabeled_videos_are_never_scored(
    golden: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """A prediction for a video that's ingested but not labeled yet must not count its cuts as false positives."""
    (golden / "v01.json").write_text(json.dumps(template([10, 50])))
    (golden / "v03.json").write_text(json.dumps(template([20, 40, 60])))
    run(monkeypatch, str(golden), "--json")
    out = json.loads(capsys.readouterr().out)
    assert set(out["videos"]) == {"v01"}
    assert out["unlabeled"] == ["v03"]
    assert out["total"]["false_positives"] == 0 and out["total"]["precision"] == 1.0

    run(monkeypatch, str(golden))
    assert "not labeled yet: v03" in capsys.readouterr().out


def test_only_unlabeled_predictions_stops(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (golden / "v03.json").write_text(json.dumps(template([20])))
    with pytest.raises(SystemExit, match="no predictions for any labeled golden video"):
        run(monkeypatch, str(golden))
