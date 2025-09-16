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

# Convert SavedModel to ONNX using command line interface
try:
    python_path = "/home/eivind/Skule/CNN/venv/bin/python"
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
