# Antithesis

[Antithesis](https://antithesis.com/) tests are designed to be executed using the [Test Composer](https://antithesis.com/docs/test_templates/). It provides a framework for creating test templates, enabling the system to manage aspects such as parallelism, test duration, and command sequencing. Antithesis uses these test templates to generate thousands of test cases, exploring various system states to uncover potential bugs.

Tests that involve sending transactions should utilize the [serial driver](https://antithesis.com/docs/test_templates/test_composer_reference/#serial-driver-command) command to prevent nonce-related issues. These commands must be executed either before or after other serial driver commands, but never concurrently.

Tests focused on reading data from the chain or any service can use the [anytime](https://antithesis.com/docs/test_templates/test_composer_reference/#anytime-command) keyword. These can run alongside both serial driver commands and other anytime commands.
