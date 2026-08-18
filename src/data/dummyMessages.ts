import type {MdMessage} from '../../modules/react-native-md-list/src';

/**
 * Dummy transcript that exercises every markdown construct ChatGPT / Gemini emit:
 * headings, emphasis, inline code, links, nested + ordered + task lists, quotes,
 * fenced code in several languages, GFM tables with alignment, rules, emoji.
 */

const ANSWER_LIST_AND_CODE = `## Cách tối ưu FlatList trong React Native

Có **4 nhóm** kỹ thuật, xếp theo mức độ hiệu quả thực tế:

1. **Giảm chi phí mỗi item**
   - Tránh inline function trong \`renderItem\`
   - Dùng \`React.memo\` cho item component
   - Không dùng \`shadow*\` trên Android, dùng \`elevation\`
2. **Giúp list ước lượng đúng**
   - Cung cấp \`getItemLayout\` khi item cao cố định
   - Đặt \`keyExtractor\` ổn định (đừng dùng index)
3. **Giảm số lần render**
   - \`windowSize\`, \`maxToRenderPerBatch\`, \`updateCellsBatchingPeriod\`
   - \`removeClippedSubviews\` trên Android
4. **Chuyển việc nặng xuống native** *(cách chúng ta đang làm ở màn này)*

\`\`\`tsx
const renderItem = useCallback(({item}: {item: Row}) => {
  return <Row data={item} />;   // memo hoá, không tạo closure mới
}, []);

<FlatList
  data={rows}
  renderItem={renderItem}
  keyExtractor={item => item.id}
  getItemLayout={(_, index) => ({
    length: ROW_HEIGHT,
    offset: ROW_HEIGHT * index,
    index,
  })}
  windowSize={7}
  maxToRenderPerBatch={8}
  removeClippedSubviews
/>
\`\`\`

> **Lưu ý:** \`getItemLayout\` chỉ dùng được khi bạn *biết trước* chiều cao.
> Với markdown chiều cao phụ thuộc nội dung, nên đo ở native rồi cache lại.

Tham khảo thêm tại [tài liệu chính thức](https://reactnative.dev/docs/optimizing-flatlist-configuration).`;

const ANSWER_TABLE = `### So sánh các cách render markdown trên mobile

| Cách tiếp cận | Thread parse | Recycle | Bảng & code block | Đánh giá |
|---|:---:|:---:|:---:|---|
| \`react-native-markdown-display\` | JS | ❌ | Cơ bản | Dễ dùng, tụt FPS khi dài |
| WebView | Renderer | ❌ | Tốt | Nặng, khó đồng bộ theme |
| Native (Kotlin/Swift) | Background | ✅ | Tốt | Mượt nhất, tốn công |
| Native + block flattening | Background | ✅✅ | Tốt | **Cách đang dùng** |

Một vài con số đo trên Pixel 6 với hội thoại 300 tin nhắn:

| Chỉ số | JS markdown | Native list |
|---|---:|---:|
| Thời gian mở màn | 1180 ms | 96 ms |
| Frame drop khi scroll nhanh | 34% | 0.4% |
| Bộ nhớ | 214 MB | 88 MB |

---

Kết luận: **flatten từng block thành một cell** là thứ tạo ra khác biệt lớn nhất,
vì nó biến một câu trả lời dài thành nhiều ô nhỏ có thể tái sử dụng.`;

const ANSWER_CODE_HEAVY = `Dưới đây là một \`suspend function\` đọc dữ liệu có timeout và retry:

\`\`\`kotlin
suspend fun <T> retryIO(
    times: Int = 3,
    initialDelay: Long = 200,
    factor: Double = 2.0,
    block: suspend () -> T
): T {
    var currentDelay = initialDelay
    repeat(times - 1) { attempt ->
        try {
            return withTimeout(5_000) { block() }
        } catch (e: IOException) {
            Log.w("retryIO", "attempt $attempt failed", e)
        }
        delay(currentDelay)
        currentDelay = (currentDelay * factor).toLong()
    }
    return block() // lần cuối, để exception ném ra ngoài
}
\`\`\`

Bản Swift tương đương:

\`\`\`swift
func retryIO<T>(
    times: Int = 3,
    initialDelay: UInt64 = 200_000_000,
    factor: Double = 2.0,
    block: () async throws -> T
) async throws -> T {
    var delay = initialDelay
    for attempt in 0..<(times - 1) {
        do {
            return try await block()
        } catch {
            print("attempt \\(attempt) failed: \\(error)")
        }
        try await Task.sleep(nanoseconds: delay)
        delay = UInt64(Double(delay) * factor)
    }
    return try await block()
}
\`\`\`

Và bản shell để kiểm tra nhanh:

\`\`\`bash
# chạy 3 lần, in ra mã trạng thái
for i in 1 2 3; do
  curl -s -o /dev/null -w "%{http_code}\\n" https://api.example.com/health
  sleep 0.2
done
\`\`\``;

const ANSWER_MIXED = `# Checklist trước khi release

## Bắt buộc

- [x] Bật Hermes và kiểm tra bundle size
- [x] Tắt \`console.log\` ở bản release
- [ ] Chạy \`detox\` trên 2 thiết bị thật
- [ ] Kiểm tra deep link \`myapp://chat/42\`

## Nên có

- Bật ProGuard/R8 và kiểm tra crash symbolication
  - Nhớ upload mapping file lên Crashlytics
  - Kiểm tra lại các class dùng reflection
- Kiểm tra Dynamic Type / font scale lớn
- Kiểm tra dark mode ở **tất cả** màn hình

> [!] Đừng quên kiểm tra màn này ở chế độ ~~light~~ **cả hai** theme.
>
> > Blockquote lồng nhau cũng phải hiển thị đúng.

Một số ký tự đặc biệt cần escape: \\*không in đậm\\*, \\\`không phải code\\\`,
và biểu thức như \`a * b * c\` phải giữ nguyên.

Emoji cũng phải đo đúng chiều cao: 🚀 🎯 ✅ 🇻🇳 👨‍👩‍👧‍👦

***

Xem thêm: https://reactnative.dev/docs/performance và <https://developer.android.com/topic/performance>`;

const ANSWER_SHORT = `Được, mình tóm tắt lại: bạn cần **một list markdown chạy mượt như ChatGPT**.

Ba điều quyết định:

1. Parse markdown **ngoài main thread**
2. Đo text **một lần** rồi cache theo \`(nội dung, bề rộng)\`
3. Mỗi block là **một cell** để tái sử dụng

Bắt đầu từ điều số 3 sẽ thấy khác biệt ngay.`;

const USER_TURNS = [
  'Làm sao để FlatList render markdown mà không bị giật?',
  'So sánh giúp mình các cách render markdown trên mobile với, có số liệu càng tốt',
  'Cho mình ví dụ code retry có timeout ở cả Kotlin và Swift nhé',
  'Trước khi release thì cần kiểm tra những gì?',
  'Tóm tắt ngắn gọn lại giúp mình',
];

const ASSISTANT_TURNS = [
  ANSWER_LIST_AND_CODE,
  ANSWER_TABLE,
  ANSWER_CODE_HEAVY,
  ANSWER_MIXED,
  ANSWER_SHORT,
];

/**
 * Builds `pairs` question/answer pairs. `offset` keeps ids unique across pages so
 * prepending an older page never collides with what is already on screen.
 */
export function buildTranscript(pairs: number, offset = 0): MdMessage[] {
  const out: MdMessage[] = [];
  for (let i = 0; i < pairs; i++) {
    const index = offset + i;
    const variant = index % USER_TURNS.length;
    out.push({
      id: `u-${index}`,
      role: 'user',
      markdown: `${USER_TURNS[variant]}${index > 4 ? ` (lần ${Math.floor(index / 5) + 1})` : ''}`,
    });
    out.push({
      id: `a-${index}`,
      role: 'assistant',
      markdown: ASSISTANT_TURNS[variant],
    });
  }
  return out;
}

/** Answer streamed token by token to demo the incremental parse path. */
export const STREAMING_ANSWER = `### Đang trả lời...

Mình sẽ giải thích **ba tầng tối ưu** mà màn hình này đang dùng.

1. **Tầng dữ liệu** — JS chỉ giữ mảng \`messages\`, không tạo view nào cho markdown.
2. **Tầng parse** — Kotlin/Swift parse markdown trên background thread và cache theo hash nội dung.
3. **Tầng layout** — mỗi block được đo *một lần* cho mỗi bề rộng, kết quả nằm trong LRU cache.

\`\`\`ts
// mỗi token mới chỉ khiến đúng một message được parse lại
setMessages(prev => prev.map(m =>
  m.id === id ? {...m, markdown: m.markdown + token} : m,
));
\`\`\`

| Tầng | Thread | Cache |
|---|:---:|---|
| Dữ liệu | JS | không |
| Parse | background | theo nội dung |
| Layout | background | theo (nội dung, width) |

> Nhờ vậy, streaming 60 token/giây vẫn chỉ tốn một lần parse mỗi frame.

Xong rồi nhé! 🎉`;
