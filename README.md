# RNApp — Markdown Chat List (native)

App demo cho `react-native-md-list`: một list chat kiểu ChatGPT / Gemini được render
**hoàn toàn bằng native** — Kotlin + RecyclerView trên Android, Swift + UITableView
trên iOS — nối vào React Native qua Fabric (New Architecture).

JS chỉ giữ mảng `messages`. Toàn bộ phần nặng (parse markdown, dựng span, đo text,
recycle cell, prefetch) nằm ở native, nên shadow tree chỉ sâu đúng 1 node và
streaming 60 token/giây vẫn không tạo thêm view nào ở phía JS.

## Ảnh chụp màn hình

| iOS (UITableView) | Android (RecyclerView) |
| --- | --- |
| <img src="markdownios.png" width="320" alt="Markdown Chat trên iOS" /> | <img src="markdownandroid.png" width="320" alt="Markdown Chat trên Android" /> |

Màn demo ([src/screens/MarkdownChatScreen.tsx](src/screens/MarkdownChatScreen.tsx))
gồm: transcript mẫu dùng đủ mọi cú pháp markdown, nút mô phỏng câu trả lời
streaming, lazy load trang lịch sử cũ hơn khi kéo lên đầu, chuyển light/dark,
nút Copy trên code block và mở link ra trình duyệt.

## Chạy thử

```sh
npm install
cd ios && bundle exec pod install && cd ..   # chỉ cần cho iOS

npm start          # Metro
npm run ios        # hoặc
npm run android
```

> Cần bật New Architecture (mặc định đã bật trên React Native 0.87).
> Sau khi sửa spec trong `modules/react-native-md-list/src`, chạy lại
> `pod install` (iOS) hoặc build lại Gradle (Android) để codegen sinh lại.

## Cấu trúc

```
modules/react-native-md-list/   thư viện native (xem README riêng của module)
src/screens/MarkdownChatScreen.tsx   màn demo
src/data/dummyMessages.ts            transcript mẫu + nội dung stream
react-native.config.js               trỏ autolinking vào module local
```

Chi tiết kiến trúc, danh sách prop và phạm vi markdown hỗ trợ nằm trong
[modules/react-native-md-list/README.md](modules/react-native-md-list/README.md).

## Dùng trong app khác

`react-native.config.js` khai báo `modules/react-native-md-list` như một local
library, autolinking lo phần Gradle và CocoaPods. Copy thư mục module sang project
khác, khai báo tương tự rồi chạy `pod install` là dùng được.
