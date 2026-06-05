# idb-repl Test Prompt

There is a skill at `fbobjc/Tools/idb/Skills/idb-repl/SKILL.md` that I would like you to load, because it explains how the `idb-repl` tool works.

I would like you to use the `idb-repl` tool to test the code in the buck target `fbsource//fbobjc/Tools/idb:ReplTest`. Please use the simulator with the UDID `66C8E69B-5EDA-4FA9-B68B-8107B9580BB2`.

I want you to come up with test cases for the `NumberMangler` class' `mangle` function. Start by coming up with what are interesting areas to test. Figure out what the input and output of the function should be for each test case. The goal is to cover as much of the function logic as possible.

Then for each test case, write some Swift code that runs the function and returns the value. This should not be formatted as a full Swift source file. There should be no `import` statements, functions or comments. This code will be executed immediately, but it needs to `return` a result at the end. Once there is a `return` statement, no other Swift statements can be executed for that test case.

Here's an example:

```swift
let result = function(10)
return result
```

Once you have Swift code for the test cases, please execute them with the `idb-repl` tool, following the instructions in the skill. Collect the result from each test case, and compare it to the *expected* value. Finally, present a list of the expected results, the actual results, and if they match or not. If they match it is a "Pass" and if they don't it is a "Fail".
