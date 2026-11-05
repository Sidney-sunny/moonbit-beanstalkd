# Independent Local Package Consumer

[Project](../README.md)

```sh
node scripts/with-beanstalkd.mjs -- node scripts/downstream-consumer.mjs
```

The check creates the actual MoonBit package ZIP, verifies its entries and CRCs, rejects credential/build paths, and extracts a fixed snapshot under ignored `_build/downstream/run-*/library`. A separate temporary consumer module imports only that extracted library through an isolated `moon.work`, using frozen dependency resolution and a fresh credential-free MoonBit home.

The consumer opens separate producer and worker connections against pinned Beanstalkd. It checks exact binary payload bytes and UInt64 job IDs, touches and deletes the job, confirms the deleted job is absent, and verifies an empty queue. Consumer source templates are original files in this directory.

Results go to `_build/downstream/result.json`, including the archive SHA256 and entry count. This proves local archive consumption and package contents; `registryInstallVerified` and `publicationPerformed` remain false. It does not claim the module has been published or installed from Mooncakes.
