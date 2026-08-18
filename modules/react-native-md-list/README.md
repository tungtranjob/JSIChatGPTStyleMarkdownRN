# react-native-md-list

List markdown kiểu ChatGPT / Gemini, render **hoàn toàn bằng native**
(Kotlin + RecyclerView trên Android, Swift + UITableView trên iOS), gọi từ React Native
qua Fabric (New Architecture).

| iOS (UITableView) | Android (RecyclerView) |
| --- | --- |
| <img src="../../markdownios.png" width="320" alt="Markdown Chat trên iOS" /> | <img src="../../markdownandroid.png" width="320" alt="Markdown Chat trên Android" /> |

```tsx
import {MarkdownChatList} from 'react-native-md-list';

<MarkdownChatList
  messages={messages}          // [{id, role: 'user' | 'assistant', markdown, streaming?}]
  colorScheme="dark"
  fontSize={16}
  loadingOlder={loadingOlder}
  onStartReached={loadOlderPage} // lazy load trang cũ hơn
  onLinkPress={Linking.openURL}
  onCodeCopy={(code, lang) => toast(`copied ${lang}`)}
/>
```

## Props truyền từ React Native xuống native

Mọi prop đều khai báo trong [`src/MdListViewNativeComponent.ts`](src/MdListViewNativeComponent.ts)
— file spec mà codegen đọc để sinh ra `MdListViewManagerInterface` (Kotlin) và
`MdListViewProps` (C++). Không có prop nào đi bằng đường "bridge tự do": nếu nó
không có trong spec thì native sẽ không bao giờ nhìn thấy.

| Prop | Kiểu | Mặc định | Đơn vị | Native làm gì với nó |
| --- | --- | --- | --- | --- |
| `messages` | `MdMessage[]` | — | — | copy sang struct thuần rồi đẩy vào pipeline parse (xem [Đường đi của một prop](#đường-đi-của-một-prop)) |
| `colorScheme` | `'light' \| 'dark'` | theo `useColorScheme()` | — | dựng lại `MdTheme` (màu chữ/nền/bubble/code/bảng) và xoá cache layout |
| `fontSize` | `number` | `16` | sp (Android) / pt (iOS) | cỡ chữ body; heading nhân `1.62 / 1.38 / 1.2 / 1.08 / 1.0 / 0.94`, code `×0.84`, ô bảng `×0.9`. Android còn nhân thêm `fontScale` của hệ thống |
| `topInset` | `number` | `0` | dp / pt | padding trên của list (chừa chỗ header) |
| `bottomInset` | `number` | `0` | dp / pt | padding dưới của list (chừa chỗ thanh soạn tin) |
| `loadingOlder` | `boolean` | `false` | — | hiện/ẩn spinner ở đầu list; khi chuyển về `false` thì mở khoá `onStartReached` cho lần kéo sau |
| `startReachedThreshold` | `number` | `600` | dp / pt | còn cách đầu list bao nhiêu thì bắn `onStartReached` |
| `prefetchRows` | `number` | `12` | row | số row ngoài viewport được layout trước ở background thread; native kẹp về khoảng `0…60` |
| `autoScrollToBottom` | `boolean` | `true` | — | có bám đáy khi nội dung mới tới và người dùng đang ở đáy hay không |

`MdMessage` là hình dạng **duy nhất** native hiểu; các field khác trong object của
bạn sẽ bị wrapper JS lược bỏ trước khi xuống native:

```ts
type MdMessage = {
  id: string;          // định danh ổn định — dùng để diff và làm key cache parse/layout
  role: 'user' | 'assistant';  // 'user' vẽ bubble căn phải, 'assistant' vẽ full-width
  markdown: string;
  streaming?: boolean; // true khi token còn đang chảy về
};
```

> `id` phải ổn định giữa các lần render. Nếu bạn sinh `id` mới mỗi lần
> `setMessages`, cache parse/layout trượt hoàn toàn và mọi lợi thế tốc độ biến mất.

### Events bắn ngược từ native lên JS

| Prop callback | Payload | Bắn khi nào |
| --- | --- | --- |
| `onStartReached` | `oldestId: string` | kéo tới gần đầu list; chỉ bắn một lần cho mỗi `oldestId` đến khi `loadingOlder` trở lại `false` |
| `onLinkPress` | `url: string` | chạm vào link hoặc autolink |
| `onCodeCopy` | `code: string`, `language: string` | bấm nút Copy trên code block (native đã copy vào clipboard sẵn, callback chỉ để hiện toast) |
| `onAtBottomChange` | `atBottom: boolean` | người dùng rời khỏi / quay lại đáy — dùng để hiện nút "xuống cuối" |
| `onVisibleRangeChange` | `firstIndex`, `lastIndex`, `blockCount` | debug/telemetry: khoảng block đang hiển thị |

Chỉ những callback bạn thực sự truyền mới được đăng ký; bỏ trống thì native
không dispatch event tương ứng.

> **Bẫy đặt tên:** React Native chuẩn hoá tên event C++ bằng cách thêm tiền tố
> `top`, nhưng bỏ qua tên nào đã bắt đầu bằng `top`. Nên prop tên `onTopReached`
> sẽ dispatch `topReached` trong khi view config đăng ký `topTopReached` → mọi
> event ném `"Unsupported top level event type"`. Đó là lý do prop này tên
> `onStartReached`.

### Commands (gọi mệnh lệnh qua ref)

```tsx
const listRef = useRef<MdListHandle>(null);

listRef.current?.scrollToBottom(true);
listRef.current?.scrollToMessage('msg-42', false);
```

Hai lệnh này đi qua `codegenNativeCommands`, tới thẳng
`MdListView.scrollToBottom` (Kotlin) / `MdListViewImpl.scrollToBottom` (Swift),
không qua vòng render nào.

## Đường đi của một prop

```
                 React (JS)
  messages/colorScheme/fontSize/…
                    │
                    ▼
   MarkdownChatList.tsx  ── lọc field thừa, chốt colorScheme mặc định
                    │
                    ▼
   MdListViewNativeComponent.ts (spec)  ── codegen sinh interface 2 phía
                    │
        ┌───────────┴────────────┐
        ▼                        ▼
   ANDROID                     iOS
   MdListViewManager.kt        MdListViewComponentView.mm
   @ReactProp setXxx()         updateProps(props, oldProps)
        │                        │  so sánh từng field với oldProps,
        │                        │  chỉ gọi setter khi khác
        ▼                        ▼
   MdListView.kt               MdListViewImpl.swift
   (RecyclerView)              (UITableView)
        └───────────┬────────────┘
                    ▼
     parse (worker) → flatten thành row → layout (worker) → diff → vẽ
```

Vài chi tiết đáng biết khi truyền prop:

- **`messages` được gộp theo frame.** Streaming đẩy mảng mới mỗi token; cả hai nền
  tảng chỉ ghi vào biến `pending` rồi post một lần parse cho frame kế tiếp
  (`main.removeCallbacks(parseRunnable)` trên Android, `scheduleParse()` trên iOS).
  Bạn không cần tự throttle ở JS.
- **iOS so sánh mảng trước khi vượt biên.** `MdMessagesEqual` trong file `.mm`
  đối chiếu từng message với props cũ, nên một lần re-render không đổi nội dung
  không tốn gì cả. Android dựa vào `AsyncListDiffer` ở tầng row.
- **Prop vô hướng thì bỏ qua nếu không đổi.** `setColorScheme` / `setFontSize`
  return sớm khi giá trị trùng — vì cả hai đều kéo theo việc dựng lại theme và xoá
  cache layout.
- **Đổi `fontSize` hoặc `colorScheme` là thao tác đắt** (đo lại toàn bộ text đang
  hiển thị). Đừng nối chúng vào một animation hay slider kéo liên tục.
- **Insets là prop, không phải style.** Đặt `topInset` / `bottomInset` thay vì bọc
  list trong `View` có padding: padding ngoài sẽ cắt mất vùng cuộn, còn inset giữ
  nội dung cuộn qua được dưới header trong suốt.
- **View bị tái sử dụng.** Fabric pool component view; `prepareForRecycle` (iOS) và
  `onDropViewInstance` (Android) xoá sạch transcript, nên đừng giả định state cũ
  còn nguyên sau khi unmount.


## Vì sao nhanh

Bốn quyết định kiến trúc, xếp theo mức ảnh hưởng:

1. **Flatten mỗi message thành nhiều row.**
   Một câu trả lời 4000 chữ không phải một cell khổng lồ, mà là ~60 block nhỏ
   (đoạn văn, heading, list item, code block, bảng). Nhờ vậy recycler chỉ đo và vẽ
   đúng phần đang hiển thị, và việc tái sử dụng view thực sự có hiệu quả.

2. **Parse markdown ngoài main thread + cache theo hash nội dung.**
   Khi streaming, mỗi token mới chỉ khiến **một** message được parse lại; toàn bộ
   lịch sử phía trên lấy từ cache. Các đợt cập nhật prop được gộp lại còn một lần
   parse mỗi frame.

3. **Đo text một lần rồi cache theo `(nội dung, bề rộng)`.**
   Android dựng `StaticLayout` (`BREAK_STRATEGY_SIMPLE`, tắt hyphenation — nhanh
   hơn mặc định vài lần), iOS dựng `CTFrame` bằng CoreText (thread-safe).
   Cả hai đều chạy trên worker thread, `onMeasure`/`heightForRowAt` chỉ đọc số đã có.

4. **Không dùng `TextView` / `UILabel`.**
   Mỗi row là một view tự vẽ `layout.draw(canvas)` / `CTFrameDraw`. Bind một row
   = gán con trỏ + `invalidate`, không dựng lại span, không đo lại chữ.

Ngoài ra: prefetch layout cho ~12 row ngoài viewport trên thread riêng
(`prefetchRowsAt` của iOS, `OnScrollListener` của Android), diff theo
prefix/suffix nên prepend một trang cũ giữ nguyên vị trí đọc, và tắt item
animator để streaming không kích hoạt animation.

## Cấu trúc

```
src/                          spec codegen + wrapper JS
android/src/main/java/com/mdlist/
  md/MarkdownParser.kt        parser block-level
  md/InlineParser.kt          parser inline (bold/italic/code/link/…)
  md/MdLayout.kt              dựng Spannable + StaticLayout, LRU cache
  md/CodeHighlighter.kt       tô màu cú pháp
  view/*.kt                   các row view tự vẽ
  MdListView.kt               RecyclerView + pipeline parse/layout
  MdListViewManager.kt        ViewManager Fabric
ios/
  MdMarkdownParser.swift      cùng thuật toán với bản Kotlin
  MdInlineParser.swift
  MdLayout.swift              CoreText + NSCache
  MdCells.swift               các cell tự vẽ
  MdListViewImpl.swift        UITableView + pipeline
  MdListViewComponentView.mm  cầu nối Fabric (mỏng)
```

## Markdown hỗ trợ

Heading (ATX + setext), đoạn văn, **đậm** / *nghiêng* / ~~gạch~~ / `code`,
link + autolink, list lồng nhau (có cả `1.` và `-`), task list `- [x]`,
blockquote lồng nhau, code fence có nhãn ngôn ngữ + nút Copy + cuộn ngang,
bảng GFM có căn lề + cuộn ngang, thematic break, escape `\*`, emoji.

**Chưa hỗ trợ:** ảnh (hiện dưới dạng nhãn 🖼 + link), công thức LaTeX,
HTML thô, và bôi đen chọn text (giữ để copy cả block thay thế).

## Hướng dẫn tích hợp

1. Copy thư mục `modules/react-native-md-list` sang project của bạn.
2. Khai báo nó như một local library trong `react-native.config.js` ở gốc project:

   ```js
   const path = require('path');

   module.exports = {
     dependencies: {
       'react-native-md-list': {
         root: path.join(__dirname, 'modules/react-native-md-list'),
       },
     },
   };
   ```

3. iOS: `cd ios && bundle exec pod install`. Android: không cần gì thêm,
   autolinking tự `include` module vào Gradle.
4. Bật New Architecture (mặc định đã bật từ React Native 0.76+). Component này là
   Fabric-only, chạy trên Paper sẽ không đăng ký được.

Một ví dụ đầy đủ hơn với ref, streaming và lazy load nằm ở màn demo
[`src/screens/MarkdownChatScreen.tsx`](../../src/screens/MarkdownChatScreen.tsx):

```tsx
const listRef = useRef<MdListHandle>(null);
const insets = useSafeAreaInsets();

<MarkdownChatList
  ref={listRef}
  messages={messages}
  colorScheme={scheme}
  fontSize={16}
  topInset={insets.top + 44}      // chừa chỗ header
  bottomInset={insets.bottom + 64} // chừa chỗ thanh soạn tin
  loadingOlder={loadingOlder}
  startReachedThreshold={600}
  prefetchRows={12}
  autoScrollToBottom
  onStartReached={oldestId => loadOlderPage(oldestId)}
  onLinkPress={url => Linking.openURL(url)}
  onCodeCopy={(_code, lang) => flashToast(`Đã copy ${lang}`)}
  onAtBottomChange={setAtBottom}
/>
```

Cập nhật một message đang stream — chỉ đụng đúng message đó để native chỉ phải
parse lại một phần tử:

```tsx
setMessages(prev =>
  prev.map(m => (m.id === id ? {...m, markdown: m.markdown + token} : m)),
);
```

Nạp trang cũ hơn thì **prepend**; diff theo prefix/suffix giữ nguyên vị trí đọc:

```tsx
const handleStartReached = useCallback(() => {
  if (loadingOlder) return;
  setLoadingOlder(true);
  fetchOlderPage().then(older => {
    setMessages(prev => [...older, ...prev]);
    setLoadingOlder(false); // trả về false mới mở khoá lần bắn tiếp theo
  });
}, [loadingOlder]);
```

## Thêm một prop mới

Prop phải được khai báo ở cả 4 chỗ, nếu thiếu một chỗ thì build vẫn chạy nhưng
giá trị lặng lẽ bị bỏ qua:

1. **Spec** — thêm field vào `NativeProps` trong
   [`src/MdListViewNativeComponent.ts`](src/MdListViewNativeComponent.ts), kèm
   `CodegenTypes.WithDefault<…>` để native có mặc định rõ ràng.
2. **Wrapper JS** — thêm vào `MarkdownChatListProps` và truyền xuống trong
   [`src/MarkdownChatList.tsx`](src/MarkdownChatList.tsx).
3. **Android** — thêm `@ReactProp` override trong
   [`android/.../MdListViewManager.kt`](android/src/main/java/com/mdlist/MdListViewManager.kt)
   (chữ ký do interface codegen sinh ra quy định) rồi xử lý trong `MdListView.kt`.
4. **iOS** — thêm nhánh so sánh trong `updateProps` của
   [`ios/MdListViewComponentView.mm`](ios/MdListViewComponentView.mm) và một
   `@objc public func setXxx` trong
   [`ios/MdListViewImpl.swift`](ios/MdListViewImpl.swift).

Sau đó chạy lại codegen: `cd ios && bundle exec pod install` cho iOS, build lại
Gradle cho Android (`npm run android`). Nếu Kotlin báo lỗi "does not override
anything" nghĩa là interface codegen chưa được sinh lại — xoá `android/build`
và `ios/build` rồi build lại.

Với event mới, nhớ thêm cả `DirectEventHandler` trong spec **và** một entry
`"topTênEvent" -> registrationName` trong `getExportedCustomDirectEventTypeConstants()`
ở phía Android.
