/// Explicit requests to quote or say something take priority over repetition checks.
bool userRequestsExactSpeech(String text) {
  final input = text.trim();
  if (RegExp(r'(不要|别|不能|不许|禁止).{0,5}(重复|复述|再说|照着|原话)').hasMatch(input)) {
    return false;
  }
  return RegExp(
    r'(再说一遍|再说一次|再讲一遍|重复一遍|重复一下|重复说|复述|照着.{0,8}说|照读|原样.{0,5}说|原话|跟我读|跟我说|学我说|你就说|你说一句|说一声|说一句|说一下|^说[：:，,\s“「"\u4e00-\u9fff]|^(请|麻烦)?(你)?(再|只)?说|\b(repeat|say exactly|say it again|quote)\b)',
    caseSensitive: false,
  ).hasMatch(input);
}
