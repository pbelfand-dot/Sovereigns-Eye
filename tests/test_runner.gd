extends Node
## Headless test runner.
##
##   godot --headless --path . res://tests/test_runner.tscn
##
## Exits with code 0 when every test passes, 1 otherwise (CI friendly).
## See tools/run_tests.sh.

const SUITES := [
	"res://tests/test_appraisal.gd",
	"res://tests/test_discovery.gd",
	"res://tests/test_generation.gd",
	"res://tests/test_save_load.gd",
	"res://tests/test_court.gd",
	"res://tests/test_recruitment.gd",
	"res://tests/test_territory.gd",
	"res://tests/test_growth.gd",
	"res://tests/test_charters.gd",
	"res://tests/test_art_pipeline.gd",
	"res://tests/test_commons.gd",
	"res://tests/test_farm.gd",
	"res://tests/test_square.gd",
	"res://tests/test_smithy.gd",
	"res://tests/test_home.gd",
	"res://tests/test_wear.gd",
	"res://tests/test_thatch.gd",
	"res://tests/test_training.gd",
	"res://tests/test_chapel.gd",
	"res://tests/test_castle.gd",
	"res://tests/test_menu.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_world_smoke.gd",
]


func _ready() -> void:
	# Defer so the runner is fully inside the tree before suites add children.
	_run.call_deferred()


func _run() -> void:
	var total := 0
	var failed: Array[String] = []
	var started := Time.get_ticks_msec()
	# TEST_FILTER=recruitment runs only the suites whose path contains it.
	var only := OS.get_environment("TEST_FILTER")
	for path in SUITES:
		if not only.is_empty() and not path.contains(only):
			continue
		var script: GDScript = load(path)
		# A parse error still returns a script, one that can't be instanced.
		if script == null or not script.can_instantiate():
			failed.append("%s: could not load" % path)
			continue
		var suite: TestCase = script.new()
		suite.runner = self
		for m in suite.get_method_list():
			var method_name: String = m["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			suite.current_test = "%s::%s" % [path.get_file().get_basename(), method_name]
			var before := suite.failures.size()
			await suite.call(method_name)
			var status := "ok" if suite.failures.size() == before else "FAIL"
			print("  [%s] %s" % [status, suite.current_test])
		failed.append_array(suite.failures)
	print("")
	for f in failed:
		printerr("FAIL  " + f)
	print("%d tests, %d failure(s) in %.1fs" % [total, failed.size(), (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failed.size() > 0 else 0)
