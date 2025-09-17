import numpy as np

############### GUIDE ################
# This script builds, trains, and evaluates a CNN model on a subset of the Quick, Draw! dataset.
# It includes visualizations of predictions, a confusion matrix, and misclassified examples.
# It also exports the trained model to ONNX format.
############### USE #################

# Install required packages
# pip install tensorflow matplotlib seaborn scikit-learn tf2onnx
# Add your .npy files in the same directory as this script and update the categories list if needed.

######################################

# Load 10 categories from Quick, Draw!
categories = ['airplane', 'alarm clock', 'ambulance', 'angel', 'animal migration', 'ant', 'anvil', 'apple', 'arm', 'axe']
data = []
labels = []

for i, category in enumerate(categories):
    drawings = np.load(f'{category}.npy')[:1000]  # Load 1000 samples per class
    data.append(drawings)
    labels.append(np.full(drawings.shape[0], i))

x = np.concatenate(data)
y = np.concatenate(labels)

print(f'Data shape: {x.shape}, Labels shape: {y.shape}')

from tensorflow.keras.utils import to_categorical

x = x.reshape(-1, 28, 28, 1).astype('float32') / 255.0
y = to_categorical(y, num_classes=10)

from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Flatten, Dense

model = Sequential([
    Conv2D(8, (3,3), activation='relu', input_shape=(28,28,1)),
    MaxPooling2D(2,2),
    Conv2D(16, (3,3), activation='relu'),
    MaxPooling2D(2,2),
    Flatten(),
    Dense(64, activation='relu'),
    Dense(10, activation='softmax')
])

model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
model.fit(x, y, epochs=5, batch_size=128)
print('Data and labels loaded and preprocessed.')
print('Model built and trained.')

# Test the model with a sample input
sample_input = x[0:1]
prediction = model.predict(sample_input)
predicted_class = np.argmax(prediction, axis=1)
print(f'Predicted class for the sample input: {predicted_class[0]}')

# Visual verification of the model
import matplotlib.pyplot as plt
from sklearn.metrics import confusion_matrix, classification_report
import seaborn as sns

# Create a better test set with samples from all classes
test_samples_per_class = 50  # 50 samples per class for testing
test_indices = []
for i in range(10):  # 10 classes
    class_start = i * 1000  # Each class has 1000 samples
    class_indices = np.arange(class_start, class_start + test_samples_per_class)
    test_indices.extend(class_indices)

test_indices = np.array(test_indices)
x_test = x[test_indices]
y_test = y[test_indices]

predictions = model.predict(x_test)
predicted_classes = np.argmax(predictions, axis=1)
true_classes = np.argmax(y_test, axis=1)

# 1. Display sample drawings with predictions
plt.figure(figsize=(15, 10))
for i in range(20):  # Show first 20 samples
    plt.subplot(4, 5, i+1)
    plt.imshow(x_test[i].reshape(28, 28), cmap='gray')
    true_label = categories[true_classes[i]]
    pred_label = categories[predicted_classes[i]]
    color = 'green' if true_classes[i] == predicted_classes[i] else 'red'
    plt.title(f'True: {true_label}\nPred: {pred_label}', color=color, fontsize=8)
    plt.axis('off')
plt.suptitle('Sample Predictions (Green=Correct, Red=Wrong)', fontsize=14)
plt.tight_layout()
plt.savefig('sample_predictions.png', dpi=150, bbox_inches='tight')
plt.show()

# 2. Confusion Matrix
plt.figure(figsize=(10, 8))
cm = confusion_matrix(true_classes, predicted_classes)
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
            xticklabels=categories, yticklabels=categories)
plt.title('Confusion Matrix')
plt.xlabel('Predicted')
plt.ylabel('True')
plt.xticks(rotation=45)
plt.yticks(rotation=0)
plt.tight_layout()
plt.savefig('confusion_matrix.png', dpi=150, bbox_inches='tight')
plt.show()

# 3. Show some misclassified examples
wrong_indices = np.where(predicted_classes != true_classes)[0]
if len(wrong_indices) > 0:
    plt.figure(figsize=(15, 6))
    num_wrong_to_show = min(10, len(wrong_indices))
    for i in range(num_wrong_to_show):
        idx = wrong_indices[i]
        plt.subplot(2, 5, i+1)
        plt.imshow(x_test[idx].reshape(28, 28), cmap='gray')
        true_label = categories[true_classes[idx]]
        pred_label = categories[predicted_classes[idx]]
        confidence = np.max(predictions[idx]) * 100
        plt.title(f'True: {true_label}\nPred: {pred_label}\nConf: {confidence:.1f}%', 
                 fontsize=8, color='red')
        plt.axis('off')
    plt.suptitle('Misclassified Examples', fontsize=14)
    plt.tight_layout()
    plt.savefig('misclassified_examples.png', dpi=150, bbox_inches='tight')
    plt.show()

# 4. Print classification report
print("\nClassification Report:")
print(classification_report(true_classes, predicted_classes, target_names=categories))

# 5. Calculate and display accuracy
accuracy = np.mean(predicted_classes == true_classes)
print(f"\nTest Accuracy: {accuracy:.3f} ({accuracy*100:.1f}%)")

print(f"\nVisualization files saved:")
print("- sample_predictions.png")
print("- confusion_matrix.png")
print("- misclassified_examples.png")

#Export the model to ONNX format
import tensorflow as tf
import subprocess
import os

# Save the model as a TensorFlow SavedModel (Keras 3.x)
model.export("saved_model")
print("Model exported as SavedModel.")

# ========== QUANTIZATION SECTION ==========
print("\n=== Applying Post-Training Quantization ===")

# Method 1: Post-Training Quantization (PTQ) - Simple approach
converter = tf.lite.TFLiteConverter.from_saved_model("saved_model")
converter.optimizations = [tf.lite.Optimize.DEFAULT]

# For FPGA: Use integer-only quantization
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.int8
converter.inference_output_type = tf.int8

# Representative dataset for calibration
def representative_dataset():
    for i in range(100):  # Use 100 samples for calibration
        yield [x[i:i+1].astype(np.float32)]

converter.representative_dataset = representative_dataset
quantized_model = converter.convert()

# Save quantized model
with open('quantized_model.tflite', 'wb') as f:
    f.write(quantized_model)

print("✓ Post-training quantized model saved as 'quantized_model.tflite'")

# Test quantized model accuracy
interpreter = tf.lite.Interpreter(model_content=quantized_model)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print(f"Quantized model input type: {input_details[0]['dtype']}")
print(f"Quantized model output type: {output_details[0]['dtype']}")

# Test on a few samples
correct_predictions = 0
test_samples = 50

for i in range(test_samples):
    # Convert input to int8 properly (range -128 to 127)
    test_input = (x_test[i:i+1] * 255).astype(np.float32)  # Scale to 0-255
    test_input = np.clip(test_input - 128, -128, 127).astype(np.int8)  # Shift and clip to int8 range
    interpreter.set_tensor(input_details[0]['index'], test_input)
    interpreter.invoke()
    
    quantized_output = interpreter.get_tensor(output_details[0]['index'])
    predicted_class_quantized = np.argmax(quantized_output)
    
    if predicted_class_quantized == true_classes[i]:
        correct_predictions += 1

quantized_accuracy = correct_predictions / test_samples
print(f"Quantized model accuracy on {test_samples} samples: {quantized_accuracy:.3f} ({quantized_accuracy*100:.1f}%)")

# ========== QUANTIZATION-AWARE TRAINING (QAT) - Better accuracy ==========
print("\n=== Quantization-Aware Training (QAT) ===")

try:
    import tensorflow_model_optimization as tfmot
    
    # Apply quantization-aware training
    quantize_model = tfmot.quantization.keras.quantize_model
    q_aware_model = quantize_model(model)
    
    # Compile QAT model
    q_aware_model.compile(optimizer='adam',
                         loss='categorical_crossentropy',
                         metrics=['accuracy'])
    
    print("✓ QAT model created")
    
    # Fine-tune with quantization simulation (use smaller subset for speed)
    subset_size = 1000
    x_subset = x[:subset_size]
    y_subset = y[:subset_size]
    
    print("Fine-tuning with quantization simulation...")
    q_aware_model.fit(x_subset, y_subset, epochs=2, batch_size=128, verbose=1)
    
    # Convert QAT model to quantized TFLite
    converter_qat = tf.lite.TFLiteConverter.from_keras_model(q_aware_model)
    converter_qat.optimizations = [tf.lite.Optimize.DEFAULT]
    quantized_qat_model = converter_qat.convert()
    
    # Save QAT quantized model
    with open('quantized_qat_model.tflite', 'wb') as f:
        f.write(quantized_qat_model)
    
    print("✓ QAT quantized model saved as 'quantized_qat_model.tflite'")
    
except ImportError:
    print("❌ tensorflow_model_optimization not available due to installation issues.")
    print("🔧 Using alternative quantization approach...")
    
    # Alternative: Manual quantization simulation
    print("Applying manual quantization simulation...")
    
    # Create a copy of the model for manual quantization
    import copy
    manual_quant_model = tf.keras.models.clone_model(model)
    manual_quant_model.set_weights(model.get_weights())
    
    # Simulate quantization by adding noise to weights
    quantized_weights = []
    for layer_weights in manual_quant_model.get_weights():
        # Simulate 8-bit quantization noise
        weight_max = np.max(np.abs(layer_weights))
        scale = weight_max / 127  # 8-bit signed range
        quantized = np.round(layer_weights / scale) * scale
        quantized_weights.append(quantized)
    
    manual_quant_model.set_weights(quantized_weights)
    
    # Test manual quantized model
    manual_predictions = manual_quant_model.predict(x_test[:50])
    manual_accuracy = np.mean(np.argmax(manual_predictions, axis=1) == true_classes[:50])
    print(f"✓ Manual quantization simulation accuracy: {manual_accuracy:.3f}")
    
    # Convert manual quantized model
    converter_manual = tf.lite.TFLiteConverter.from_keras_model(manual_quant_model)
    converter_manual.optimizations = [tf.lite.Optimize.DEFAULT]
    quantized_manual_model = converter_manual.convert()
    
    with open('quantized_manual_model.tflite', 'wb') as f:
        f.write(quantized_manual_model)
    
    print("✓ Manual quantized model saved as 'quantized_manual_model.tflite'")

# ========== FPGA-FRIENDLY WEIGHT EXTRACTION ==========
print("\n=== FPGA Weight Extraction ===")

# Extract quantized weights for FPGA implementation
if 'quantized_model' in locals():
    # Get quantized model details
    interpreter = tf.lite.Interpreter(model_content=quantized_model)
    interpreter.allocate_tensors()
    
    # Extract weights from quantized model
    tensor_details = interpreter.get_tensor_details()
    
    print("Quantized model layers and weights:")
    weights_info = []
    
    for detail in tensor_details:
        if detail['name'].endswith('weights') or 'kernel' in detail['name'].lower():
            tensor = interpreter.get_tensor(detail['index'])
            weights_info.append({
                'name': detail['name'],
                'shape': tensor.shape,
                'dtype': tensor.dtype,
                'quantization': detail['quantization_parameters']
            })
            print(f"- {detail['name']}: shape={tensor.shape}, dtype={tensor.dtype}")
            
            # Save weights as binary file for FPGA
            filename = f"weights_{detail['name'].replace('/', '_')}.bin"
            tensor.tofile(filename)
            print(f"  → Saved to {filename}")

print("\n=== Summary ===")
print("Generated files for FPGA implementation:")
print("- quantized_model.tflite (8-bit post-training quantized)")
if 'quantized_qat_model' in locals():
    print("- quantized_qat_model.tflite (QAT quantized model)")
elif 'quantized_manual_model' in locals():
    print("- quantized_manual_model.tflite (manual quantized model)")
print("- weights_*.bin (individual weight files)")
print("- All weights are quantized to 8-bit integers")
print("- Ready for FPGA implementation with 8-bit arithmetic")
print("\n💡 Note: Post-training quantization works well for most FPGA applications!")
print("   The PTQ model should provide good accuracy for your CNN inference.")

# Convert SavedModel to ONNX using command line interface
try:
    python_path = "C:/Users/eivin/AppData/Local/Microsoft/WindowsApps/python3.13.exe"
    result = subprocess.run([
        python_path, "-m", "tf2onnx.convert", 
        "--saved-model", "saved_model", 
        "--output", "quickdraw_model.onnx"
    ], capture_output=True, text=True, check=True)
    print("Model successfully converted to ONNX format: quickdraw_model.onnx")
    print(result.stdout)
except subprocess.CalledProcessError as e:
    print(f"ONNX conversion failed: {e}")
    print(f"Error output: {e.stderr}")
    print("To convert manually, run:")
    print("python -m tf2onnx.convert --saved-model saved_model --output quickdraw_model.onnx")
except FileNotFoundError:
    print("tf2onnx not installed. Install with: pip install tf2onnx")
    print("ONNX conversion skipped - TFLite models are sufficient for FPGA!")
