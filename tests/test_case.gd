class_name TestCase
extends RefCounted
## Minimal test base class. Any method starting with "test_" is run by
## tests/test_runner.gd. Methods may `await` (the runner awaits each one).

var failures: Array[String] = []
var current_test: String = ""
## The runner node, so tests can add scenes to the tree and await frames.
var runner: Node


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: %s (expected %s, got %s)" % [current_test, message, str(expected), str(actual)])


func frames(count: int) -> void:
	for i in count:
		await runner.get_tree().process_frame
