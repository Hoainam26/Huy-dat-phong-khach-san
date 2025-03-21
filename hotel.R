# Cài đặt và nạp thư viện
library(sparklyr)
library(dplyr)
library(ggplot2)
library(caret)
library(e1071)

# 1. Kết nối với Spark
sc <- spark_connect(master = "local")

# 2. Đọc dữ liệu từ file CSV
hotel_data <- spark_read_csv(sc, 
                             name = "hotel_reservations", 
                             path = "C:/Users/User/OneDrive/Desktop/Giang/Năm 3/Kỳ 2/T2- Du Lieu Lon/BKT/Hotel_Reservations_Modified_Updated.csv", 
                             infer_schema = TRUE, 
                             header = TRUE)

# 3. Kiểm tra danh sách cột có 'arrival_date_month' không
if (!"arrival_date_month" %in% colnames(hotel_data)) {
  hotel_data <- hotel_data %>%
    mutate(arrival_date_month = format(as.Date(arrival_date, format="%Y-%m-%d"), "%B"))
}

# 4. Tiền xử lý dữ liệu
hotel_data <- hotel_data %>%
  mutate(booking_status = ifelse(booking_status == "Canceled", 1, 0)) %>%
  ft_string_indexer(input_col = "type_of_meal_plan", output_col = "type_of_meal_plan_index") %>%
  ft_string_indexer(input_col = "room_type_reserved", output_col = "room_type_reserved_index") %>%
  ft_string_indexer(input_col = "market_segment_type", output_col = "market_segment_type_index")

# 5. Loại bỏ các cột không cần thiết
data_tbl <- hotel_data %>%
  select(-Booking_ID, -type_of_meal_plan, -room_type_reserved, -market_segment_type)

# 6. Chia dữ liệu thành tập huấn luyện (70%) và kiểm tra (30%)
splits <- sdf_partition(data_tbl, training = 0.7, testing = 0.3, seed = 42)
training_data <- splits$training
testing_data <- splits$testing

# 7. Huấn luyện mô hình Random Forest
rf_model <- training_data %>%
  ml_random_forest(booking_status ~ ., type = "classification", num_trees = 100, seed = 42)

# 8. Dự đoán trên tập kiểm tra
test_predictions <- ml_predict(rf_model, testing_data)

# 9. Đánh giá mô hình
accuracy <- test_predictions %>%
  summarise(accuracy = mean(as.integer(prediction) == booking_status)) %>%
  collect()

cat("Độ chính xác của mô hình Random Forest:", round(accuracy$accuracy * 100, 2), "%\n")

# -------------------------
# 10. Phân tích dữ liệu với biểu đồ
# -------------------------

# a) Tỷ lệ đặt phòng bị hủy (Pie Chart)
booking_trend <- hotel_data %>%
  group_by(booking_status) %>%
  summarise(count = n()) %>%
  collect() %>%
  mutate(booking_status = ifelse(booking_status == 1, "Canceled", "Not Canceled"))

if (nrow(booking_trend) > 0) {
  p1 <- ggplot(booking_trend, aes(x = "", y = count, fill = booking_status)) +
    geom_bar(stat = "identity", width = 1) +
    coord_polar("y", start = 0) +
    labs(title = "Tỷ lệ đặt phòng bị hủy vs không hủy") +
    theme_minimal()
  print(p1)
} else {
  cat("Không có dữ liệu để vẽ biểu đồ tỷ lệ đặt phòng bị hủy.\n")
}

# b) Xu hướng đặt phòng theo tháng (Bar Chart)
monthly_trend <- hotel_data %>%
  group_by(arrival_date_month) %>%
  summarise(count = n()) %>%
  collect()

if (nrow(monthly_trend) > 0) {
  p2 <- ggplot(monthly_trend, aes(x = arrival_date_month, y = count, fill = count)) +
    geom_bar(stat = "identity") +
    labs(title = "Số lượng đặt phòng theo tháng",
         x = "Tháng",
         y = "Số lượt đặt") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))  # Xoay nhãn trục X
  
  print(p2)
} else {
  cat("Không có dữ liệu để vẽ biểu đồ đặt phòng theo tháng.\n")
}

# c) Xu hướng đặt phòng theo phân khúc khách hàng (Bar Chart)
customer_trend <- hotel_data %>%
  group_by(market_segment_type) %>%
  summarise(count = n()) %>%
  collect()

if (nrow(customer_trend) > 0) {
  p3 <- ggplot(customer_trend, aes(x = reorder(market_segment_type, count), y = count, fill = market_segment_type)) +
    geom_bar(stat = "identity") +
    coord_flip() +
    labs(title = "Xu hướng đặt phòng theo phân khúc khách hàng",
         x = "Phân khúc khách hàng",
         y = "Số lượt đặt") +
    theme_minimal()
  print(p3)
} else {
  cat("Không có dữ liệu để vẽ biểu đồ phân khúc khách hàng.\n")
}

# 11. Ngắt kết nối Spark
spark_disconnect(sc)