import Foundation

/// Reviewed text/tool checkpoints. Pin revisions and hashes so upstream changes
/// cannot silently change what a model downloads. No Hub code is run.
public struct AppleDownloadableModel: Identifiable, Sendable {
    public var id: String { repository }
    public let name: String
    /// One line on what the model is good for and the memory it suits.
    public let summary: String
    /// Physical memory, in GiB, the model runs comfortably with.
    public let memory: Int
    public let repository: String
    public let revision: String
    let files: [File]

    public var byteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }
    public var sourceURL: URL { URL(string: "https://huggingface.co/\(repository)")! }

    struct File: Sendable {
        let name: String
        let byteCount: Int64
        let digest: Digest
    }

    enum Digest: Sendable {
        case sha256(String)
        case gitSHA1(String)
    }

    /// The most capable model that runs comfortably in this much physical memory.
    /// Among models wanting the same memory, the first listed is the reviewed default.
    public static func recommended(forPhysicalMemory bytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Self? {
        available.filter { UInt64($0.memory) << 30 <= bytes }
            .reduce(nil) { best, next in best.map { next.memory > $0.memory ? next : $0 } ?? next }
    }

    /// Listed smallest first, so capability and memory needs rise down the list.
    public static let available: [Self] = [
        .init(name: "Qwen3 1.7B", summary: "Smallest and fastest. Handles simple tool calls when memory is tight.", memory: 0,
              repository: "mlx-community/Qwen3-1.7B-4bit",
              revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e", files: [
                .init(name: "special_tokens_map.json", byteCount: 613, digest: .gitSHA1("ac23c0aaa2434523c494330aeb79c58395378103")),
                .init(name: "added_tokens.json", byteCount: 707, digest: .gitSHA1("b54f9135e44c1e81047e8d05cb027af8bc039eed")),
                .init(name: "config.json", byteCount: 937, digest: .gitSHA1("0a78ffc3980b062021a450199988d0ed8537239d")),
                .init(name: "tokenizer_config.json", byteCount: 9706, digest: .gitSHA1("7345216a0785dc7086e8c245b2a9d3896ce2b756")),
                .init(name: "model.safetensors.index.json", byteCount: 49731, digest: .gitSHA1("8607d041b6549c15a4db85e7b4c5cf30d3ab890a")),
                .init(name: "merges.txt", byteCount: 1671853, digest: .gitSHA1("31349551d90c7606f325fe0f11bbb8bd5fa0d7c7")),
                .init(name: "vocab.json", byteCount: 2776833, digest: .gitSHA1("4783fe10ac3adce15ac8f358ef5462739852c569")),
                .init(name: "tokenizer.json", byteCount: 11422654, digest: .sha256("aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4")),
                .init(name: "model.safetensors", byteCount: 968080210, digest: .sha256("0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f")),
              ]),
        .init(name: "Qwen3 4B Instruct", summary: "Answers directly without thinking first. Reliable tool calls; suits 8 GB of memory.", memory: 8,
              repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
              revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b", files: [
                .init(name: "generation_config.json", byteCount: 238, digest: .gitSHA1("432531a002c181a19de338313d2375e9d7494d7e")),
                .init(name: "special_tokens_map.json", byteCount: 613, digest: .gitSHA1("ac23c0aaa2434523c494330aeb79c58395378103")),
                .init(name: "added_tokens.json", byteCount: 707, digest: .gitSHA1("b54f9135e44c1e81047e8d05cb027af8bc039eed")),
                .init(name: "config.json", byteCount: 938, digest: .gitSHA1("ce8b8eccd1cdf6d8a30767f58e8ff858dd15eab5")),
                .init(name: "chat_template.jinja", byteCount: 4040, digest: .gitSHA1("a18870ad4ba26ac6c43758fc506c1bb6ff206bb4")),
                .init(name: "tokenizer_config.json", byteCount: 5440, digest: .gitSHA1("474bbcd82077828bdec32b8dbc1826cdff2a792a")),
                .init(name: "model.safetensors.index.json", byteCount: 63964, digest: .gitSHA1("4741a210f9920c2949ca73bbb2a7ce9583e7fd83")),
                .init(name: "merges.txt", byteCount: 1671853, digest: .gitSHA1("31349551d90c7606f325fe0f11bbb8bd5fa0d7c7")),
                .init(name: "vocab.json", byteCount: 2776833, digest: .gitSHA1("4783fe10ac3adce15ac8f358ef5462739852c569")),
                .init(name: "tokenizer.json", byteCount: 11422654, digest: .sha256("aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4")),
                .init(name: "model.safetensors", byteCount: 2263022417, digest: .sha256("2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f")),
              ]),
        .init(name: "Qwen3 8B", summary: "Thinks before answering, for steadier multi-step tool use. Best with 16 GB of memory.", memory: 16,
              repository: "mlx-community/Qwen3-8B-4bit",
              revision: "545dc4251c05440727734bcd94334791f6ab0192", files: [
                .init(name: "special_tokens_map.json", byteCount: 613, digest: .gitSHA1("ac23c0aaa2434523c494330aeb79c58395378103")),
                .init(name: "added_tokens.json", byteCount: 707, digest: .gitSHA1("b54f9135e44c1e81047e8d05cb027af8bc039eed")),
                .init(name: "config.json", byteCount: 939, digest: .gitSHA1("6f2a32b76648381bea25bdc81fad0e7160f86ac5")),
                .init(name: "tokenizer_config.json", byteCount: 9706, digest: .gitSHA1("7345216a0785dc7086e8c245b2a9d3896ce2b756")),
                .init(name: "model.safetensors.index.json", byteCount: 64065, digest: .gitSHA1("4af62897c345f277e7b17aab48230d7ba119d87e")),
                .init(name: "merges.txt", byteCount: 1671853, digest: .gitSHA1("31349551d90c7606f325fe0f11bbb8bd5fa0d7c7")),
                .init(name: "vocab.json", byteCount: 2776833, digest: .gitSHA1("4783fe10ac3adce15ac8f358ef5462739852c569")),
                .init(name: "tokenizer.json", byteCount: 11422654, digest: .sha256("aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4")),
                .init(name: "model.safetensors", byteCount: 4607835174, digest: .sha256("f2d29621aab300336ad645567ff38c42aac755513006ef4e8a579cf7ef5256d8")),
              ]),
        .init(name: "Gemma 4 E4B", summary: "Google’s compact model. Quick replies and tool calls without thinking first. Best with 16 GB of memory.", memory: 16,
              repository: "mlx-community/gemma-4-e4b-it-4bit",
              revision: "475b9088d29754a3379866cf5aeb6b41acd313c2", files: [
                .init(name: "generation_config.json", byteCount: 208, digest: .gitSHA1("e605bb4523b1462ea9d9a3810b9e3ecf7ab7b1f6")),
                .init(name: "processor_config.json", byteCount: 1316, digest: .gitSHA1("a086fb7e04b477c291a120b0a004abb78b11c6d2")),
                .init(name: "tokenizer_config.json", byteCount: 2740, digest: .gitSHA1("cf6235aee46a24bf71f251c0a4e7a0379948f7d2")),
                .init(name: "config.json", byteCount: 6628, digest: .gitSHA1("4ee08502c4f98810dd43800ec849bd69f94adc98")),
                .init(name: "chat_template.jinja", byteCount: 17336, digest: .gitSHA1("c19999a347da729cf62806a8ddb7eb8e315223b5")),
                .init(name: "model.safetensors.index.json", byteCount: 240961, digest: .gitSHA1("c03ce5f7086b735345038501f731634de064493b")),
                .init(name: "tokenizer.json", byteCount: 32169626, digest: .sha256("cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f")),
                .init(name: "model.safetensors", byteCount: 5146800534, digest: .sha256("932b8271fc3fe65adcc78b96c10c6268bbfb13e8f67d1358727c0d6ee97e1eff")),
              ]),
        .init(name: "Qwen3.5 9B", summary: "A newer Qwen that thinks before answering, for multi-step tool use. Best with 16 GB of memory.", memory: 16,
              repository: "mlx-community/Qwen3.5-9B-MLX-4bit",
              revision: "938d8919941c6e7efd3c7150eff7fe9d12afa631", files: [
                .init(name: "video_preprocessor_config.json", byteCount: 385, digest: .gitSHA1("3ba673a5ad7d4d13f54155ecd38b2a94a6dac8fe")),
                .init(name: "preprocessor_config.json", byteCount: 390, digest: .gitSHA1("2ea84a437d448ff71b08df68fdd949d5cc4ebb64")),
                .init(name: "tokenizer_config.json", byteCount: 1139, digest: .gitSHA1("a068e2468cff426a9b105006e74e044030a6faf4")),
                .init(name: "processor_config.json", byteCount: 1300, digest: .gitSHA1("7ad6acdf4203f22b7b990e36ccc3a1fe38563d5e")),
                .init(name: "config.json", byteCount: 3331, digest: .gitSHA1("0435ae3f4b3c8b907f7359a2f8f7150d316f3435")),
                .init(name: "chat_template.jinja", byteCount: 7756, digest: .gitSHA1("a585dec894e63da457d9440ec6aa7caa16d20860")),
                .init(name: "model.safetensors.index.json", byteCount: 123592, digest: .gitSHA1("d366fa524ccd8f4ed93a67c7857597dc56172b92")),
                .init(name: "vocab.json", byteCount: 6722759, digest: .gitSHA1("0aa0ce0658d60ac4a5d609f4eadb0e8e43514176")),
                .init(name: "tokenizer.json", byteCount: 19989343, digest: .sha256("87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4")),
                .init(name: "model-00002-of-00002.safetensors", byteCount: 600449850, digest: .sha256("b0a770bf8469c7f3f18756a0e0283f1c1174344a83e059a4e483f6af4907352d")),
                .init(name: "model-00001-of-00002.safetensors", byteCount: 5349771222, digest: .sha256("a68b87558c6ef43f74c2bd63ce7e9092ceddc3101f3def0030774bae5f42aadd")),
              ]),
        .init(name: "Qwen3 14B", summary: "Deeper reasoning and tool use than Qwen3 8B. Best with 24 GB of memory.", memory: 24,
              repository: "mlx-community/Qwen3-14B-4bit",
              revision: "a4d9b2df59d2c150bef02fcbe0d91046b7ca33a4", files: [
                .init(name: "special_tokens_map.json", byteCount: 613, digest: .gitSHA1("ac23c0aaa2434523c494330aeb79c58395378103")),
                .init(name: "added_tokens.json", byteCount: 707, digest: .gitSHA1("b54f9135e44c1e81047e8d05cb027af8bc039eed")),
                .init(name: "config.json", byteCount: 939, digest: .gitSHA1("38386939cee12ed747ace23c207f2d1f1ea111e5")),
                .init(name: "tokenizer_config.json", byteCount: 9706, digest: .gitSHA1("7345216a0785dc7086e8c245b2a9d3896ce2b756")),
                .init(name: "model.safetensors.index.json", byteCount: 86266, digest: .gitSHA1("7ca9a1b8e12ec323d0c74fb3bc3cbf8269aaabdc")),
                .init(name: "merges.txt", byteCount: 1671853, digest: .gitSHA1("31349551d90c7606f325fe0f11bbb8bd5fa0d7c7")),
                .init(name: "vocab.json", byteCount: 2776833, digest: .gitSHA1("4783fe10ac3adce15ac8f358ef5462739852c569")),
                .init(name: "tokenizer.json", byteCount: 11422654, digest: .sha256("aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4")),
                .init(name: "model-00002-of-00002.safetensors", byteCount: 2953517134, digest: .sha256("2814562d654fe2d541fd4682804a0ccaa400e79701872c8e9f5998cf9481fdf8")),
                .init(name: "model-00001-of-00002.safetensors", byteCount: 5354381380, digest: .sha256("5795efcfc7c96fd273e600562e8b111bfcc427415de9001d0a07e70cd99cff19")),
              ]),
        .init(name: "gpt-oss 20B", summary: "OpenAI’s open model. Reasons before answering. Best with 24 GB of memory.", memory: 24,
              repository: "mlx-community/gpt-oss-20b-MXFP4-Q8",
              revision: "773a7da77e569019bb0fd17a554b263738d669a3", files: [
                .init(name: "generation_config.json", byteCount: 177, digest: .gitSHA1("86f91466555bd40e3de0b1edee3d5d82f4ccdbfe")),
                .init(name: "special_tokens_map.json", byteCount: 440, digest: .gitSHA1("6274cc1bd159aa75de771315558e5cac7dd8bea0")),
                .init(name: "chat_template.jinja", byteCount: 16738, digest: .gitSHA1("dc7bb11927d29f653ba2740f2db2c688fd77592f")),
                .init(name: "tokenizer_config.json", byteCount: 21694, digest: .gitSHA1("b77ce0aa2ad60df5a9167bae1164ff664ccdce86")),
                .init(name: "config.json", byteCount: 33998, digest: .gitSHA1("1b1f1390d5dfc715e504996ce0e8a22da5342cba")),
                .init(name: "model.safetensors.index.json", byteCount: 67046, digest: .gitSHA1("1e72dcd5a66651e4f5f9a26b03602f798669ab2e")),
                .init(name: "tokenizer.json", byteCount: 27868174, digest: .sha256("0614fe83cadab421296e664e1f48f4261fa8fef6e03e63bb75c20f38e37d07d3")),
                .init(name: "model-00003-of-00003.safetensors", byteCount: 1490905743, digest: .sha256("16c32bb8dbd1fa8d556815706589d6d6480d29946196cd2fe2b721d4daf84132")),
                .init(name: "model-00002-of-00003.safetensors", byteCount: 5281581967, digest: .sha256("4a862a873080e489db16125877e19553b958562ff4dd0246135bc061c3293652")),
                .init(name: "model-00001-of-00003.safetensors", byteCount: 5303719858, digest: .sha256("57f4846924652b1b23537c6c6d6b65f64fde811e47369d4e23c5c45b4d7584a7")),
              ]),
        .init(name: "Qwen3.8 27B", summary: "The newest Qwen. Strong reasoning and tool use, at a slower pace. Best with 32 GB of memory.", memory: 32,
              repository: "mlx-community/Qwen3.8-27B-4bit",
              revision: "10c35caafbb80f7dc6a7a432cdd11af10a6d4818", files: [
                .init(name: "generation_config.json", byteCount: 202, digest: .gitSHA1("023756cfadf88e5bf69eefeee3e172f38c448d64")),
                .init(name: "video_preprocessor_config.json", byteCount: 385, digest: .gitSHA1("3ba673a5ad7d4d13f54155ecd38b2a94a6dac8fe")),
                .init(name: "preprocessor_config.json", byteCount: 390, digest: .gitSHA1("2ea84a437d448ff71b08df68fdd949d5cc4ebb64")),
                .init(name: "processor_config.json", byteCount: 991, digest: .gitSHA1("4bbac788e2cf449e619d7fee64f206c793a4695e")),
                .init(name: "tokenizer_config.json", byteCount: 1165, digest: .gitSHA1("1d134cd298be1e3be25db393d93a1cefe80e3214")),
                .init(name: "config.json", byteCount: 4932, digest: .gitSHA1("3fb03e916f494e6745aa23df751da26f79e06470")),
                .init(name: "chat_template.jinja", byteCount: 8952, digest: .gitSHA1("c0c686f9c38d70d179fb7b5f5aa7530bc913dda3")),
                .init(name: "model.safetensors.index.json", byteCount: 218281, digest: .gitSHA1("05a3a3a17368d54d2887783e96b3a8191e9655f0")),
                .init(name: "vocab.json", byteCount: 6722759, digest: .gitSHA1("0aa0ce0658d60ac4a5d609f4eadb0e8e43514176")),
                .init(name: "tokenizer.json", byteCount: 19989325, digest: .sha256("06b9509352d2af50381ab2247e083b80d32d5c0aba91c272ca9ff729b6a0e523")),
                .init(name: "model-00001-of-00003.safetensors", byteCount: 5343268662, digest: .sha256("6cc1508e96fb5d0865dfd5753a79f4ec60651bf3e2a82844a7e8ae9c60528c0d")),
                .init(name: "model-00002-of-00003.safetensors", byteCount: 5354185130, digest: .sha256("83f2a20ca8058f486a3634a27faf99587f4cd3c156a83dee34fb99e6ac178670")),
                .init(name: "model-00003-of-00003.safetensors", byteCount: 5357087557, digest: .sha256("31b8c91ef899f79efaaa69e3d2c096f6e2ebeb2ff20e29222abbd9ebc79e560a")),
              ]),
        .init(name: "Qwen3.6 35B-A3B", summary: "Uses a small part of itself for each word, so it replies quickly for its size. Best with 32 GB of memory.", memory: 32,
              repository: "mlx-community/Qwen3.6-35B-A3B-4bit",
              revision: "38740b847e4cb78f352aba30aa41c76e08e6eb46", files: [
                .init(name: "configuration.json", byteCount: 58, digest: .gitSHA1("d24dba949ee1fe70cc810e4c4709a0bddf4e06ba")),
                .init(name: "generation_config.json", byteCount: 202, digest: .gitSHA1("023756cfadf88e5bf69eefeee3e172f38c448d64")),
                .init(name: "video_preprocessor_config.json", byteCount: 385, digest: .gitSHA1("3ba673a5ad7d4d13f54155ecd38b2a94a6dac8fe")),
                .init(name: "preprocessor_config.json", byteCount: 390, digest: .gitSHA1("2ea84a437d448ff71b08df68fdd949d5cc4ebb64")),
                .init(name: "tokenizer_config.json", byteCount: 1139, digest: .gitSHA1("a068e2468cff426a9b105006e74e044030a6faf4")),
                .init(name: "processor_config.json", byteCount: 1312, digest: .gitSHA1("a3be3e79470d0a5befe0ba5247dfad8717d84529")),
                .init(name: "chat_template.jinja", byteCount: 7764, digest: .gitSHA1("a8755d827c0a7b614c246c4060dfd58ab352a8ff")),
                .init(name: "config.json", byteCount: 23591, digest: .gitSHA1("e3a2334ebf2df216742ef3ed4b784417bfffe6fc")),
                .init(name: "model.safetensors.index.json", byteCount: 215755, digest: .gitSHA1("f714d295484e01790bad8b40c2ce49323d7d2598")),
                .init(name: "vocab.json", byteCount: 6722759, digest: .gitSHA1("0aa0ce0658d60ac4a5d609f4eadb0e8e43514176")),
                .init(name: "tokenizer.json", byteCount: 19989343, digest: .sha256("87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4")),
                .init(name: "model-00004-of-00004.safetensors", byteCount: 4377211365, digest: .sha256("a5d0cf03519c26f8b506df6b0ba60526e5c08c8cea22d0c21ce92950e58a5422")),
                .init(name: "model-00001-of-00004.safetensors", byteCount: 5288196018, digest: .sha256("09f3e6ecb0b7af6e6a38bc8169a134c821b0924c2679b2bb8f4426ad38d032b8")),
                .init(name: "model-00003-of-00004.safetensors", byteCount: 5368324139, digest: .sha256("3e66de06a1f03dade16a612a368cfce4a4c9caa4efd7d28185454384082cec03")),
                .init(name: "model-00002-of-00004.safetensors", byteCount: 5368472749, digest: .sha256("31dcdb1c49eebdb1505bd14e3cb33f9cf900bd2546b638f2464694ae763a033f")),
              ]),
        .init(name: "Qwen3 Coder Next", summary: "Built for long agentic tasks and code, and quick for its size. Best with 64 GB of memory.", memory: 64,
              repository: "mlx-community/Qwen3-Coder-Next-4bit",
              revision: "7b9321eabb85ce79625cac3f61ea691e4ea984b5", files: [
                .init(name: "generation_config.json", byteCount: 214, digest: .gitSHA1("022ede02b13f6204bb4994da82c1d9d627abe288")),
                .init(name: "tokenizer_config.json", byteCount: 702, digest: .gitSHA1("b1ec3422072fdfdd6794d9b6877b3d0df244d0a2")),
                .init(name: "chat_template.jinja", byteCount: 6068, digest: .gitSHA1("1ac848e36c5e24a7f31f64b5631eb8890ffe916f")),
                .init(name: "config.json", byteCount: 22196, digest: .gitSHA1("d80da1d432a20bf5d18fc89b08119fc8c577132e")),
                .init(name: "model.safetensors.index.json", byteCount: 173450, digest: .gitSHA1("4ab1dfa6652469a9951b275dad93ac7e58cce504")),
                .init(name: "tokenizer.json", byteCount: 11422650, digest: .sha256("be75606093db2094d7cd20f3c2f385c212750648bd6ea4fb2bf507a6a4c55506")),
                .init(name: "model-00009-of-00009.safetensors", byteCount: 2934865732, digest: .sha256("933efe2e2f28f97b9b851839c43fca0d6742b26c9ff9df1fd0e427712246553c")),
                .init(name: "model-00001-of-00009.safetensors", byteCount: 5132893190, digest: .sha256("fb30a2722004cb427d9dc3b3583a9dc4f94badf68420393324e6ebee4432c96f")),
                .init(name: "model-00006-of-00009.safetensors", byteCount: 5239714662, digest: .sha256("37f9b2ff202e8d58239f1df6acc568cb08e10a324b57c19f21b38ce93608b8c0")),
                .init(name: "model-00003-of-00009.safetensors", byteCount: 5239714716, digest: .sha256("0b8e009bd09fb5994d4d188a61e28a90aead48a50d7e0983d3bd7fc3644553d3")),
                .init(name: "model-00002-of-00009.safetensors", byteCount: 5257948500, digest: .sha256("a6b2a95a4bb7463f74951a5565e2504e7f28fe78877bb966378003b0def69038")),
                .init(name: "model-00005-of-00009.safetensors", byteCount: 5257948651, digest: .sha256("f19b843ee11c5b4c8d56b2a5940033e81ec29013de75d944447754238344621b")),
                .init(name: "model-00007-of-00009.safetensors", byteCount: 5257948739, digest: .sha256("78e4b432212f783db393bc643b9875918fc050c3d3c41a071bf9260449db356a")),
                .init(name: "model-00004-of-00009.safetensors", byteCount: 5261626153, digest: .sha256("6b34fd01a609db8bd4e445dcc0cc1ef5991550523b4df7e89f59c7d50343e321")),
                .init(name: "model-00008-of-00009.safetensors", byteCount: 5261626157, digest: .sha256("3841f088f9ceed8f4024e0c6496677af6b6a32047f762337b6d42232261cb3dc")),
              ]),
    ]
}
