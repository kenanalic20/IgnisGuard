#!/usr/bin/env python3

"""Train a Random Forest classifier from Excel data.

Expected columns:
- temperature
- humidity
- gas
- class

Classes are expected to be one of: Good, Warning, Danger.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder


FEATURE_COLUMNS = ["temperature", "humidity", "gas"]
TARGET_COLUMN = "class"
VALID_CLASSES = {"Good", "Warning", "Danger"}


def load_and_validate_dataset(excel_path: Path) -> pd.DataFrame:
	"""Load data from Excel and validate required columns/classes."""
	df = pd.read_excel(excel_path)

	missing_columns = [
		column for column in FEATURE_COLUMNS + [TARGET_COLUMN] if column not in df.columns
	]
	if missing_columns:
		raise ValueError(
			f"Missing required columns: {missing_columns}. "
			f"Required columns are: {FEATURE_COLUMNS + [TARGET_COLUMN]}"
		)

	cleaned = df[FEATURE_COLUMNS + [TARGET_COLUMN]].dropna().copy()

	unexpected_classes = set(cleaned[TARGET_COLUMN].astype(str)) - VALID_CLASSES
	if unexpected_classes:
		raise ValueError(
			f"Unexpected class values found: {sorted(unexpected_classes)}. "
			f"Allowed values are: {sorted(VALID_CLASSES)}"
		)

	cleaned[TARGET_COLUMN] = cleaned[TARGET_COLUMN].astype(str)
	return cleaned


def train_model(
	dataset: pd.DataFrame,
	random_state: int,
	n_estimators: int,
) -> tuple[RandomForestClassifier, LabelEncoder, str, pd.DataFrame]:
	"""Train the model and return artifacts plus evaluation text."""
	x = dataset[FEATURE_COLUMNS]
	y_text = dataset[TARGET_COLUMN]

	label_encoder = LabelEncoder()
	y = label_encoder.fit_transform(y_text)

	x_train, x_test, y_train, y_test = train_test_split(
		x,
		y,
		test_size=0.2,
		random_state=random_state,
		stratify=y,
	)

	model = RandomForestClassifier(
					n_estimators=n_estimators,
					random_state=random_state,
					class_weight="balanced",
				)
		

	model.fit(x_train, y_train)
	y_pred = model.predict(x_test)

	report = classification_report(
		y_test,
		y_pred,
		target_names=label_encoder.classes_,
		digits=4,
	)

	matrix = confusion_matrix(y_test, y_pred)
	matrix_df = pd.DataFrame(
		matrix,
		index=[f"actual_{name}" for name in label_encoder.classes_],
		columns=[f"pred_{name}" for name in label_encoder.classes_],
	)

	return model, label_encoder, report, matrix_df


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(
		description="Train Random Forest classifier from an Excel file.",
		epilog=(
			"Example: python main.py --data training_data.xlsx --model-out model_rf.joblib"
		)
	)
	parser.add_argument(
		"--data",
		required=True,
		help="Path to input Excel file (.xlsx/.xls)",
	)
	parser.add_argument(
		"--model-out",
		default="model_rf.joblib",
		help="Output path for trained model artifact",
	)
	parser.add_argument(
		"--random-state",
		type=int,
		default=42,
		help="Random seed for reproducibility",
	)
	parser.add_argument(
		"--n-estimators",
		type=int,
		default=200,
		help="Number of trees in the forest",
	)
	return parser.parse_args()


def main() -> None:
	args = parse_args()
	excel_path = Path(args.data)

	if not excel_path.exists():
		raise FileNotFoundError(f"Excel file not found: {excel_path}")

	dataset = load_and_validate_dataset(excel_path)
	model, label_encoder, report, matrix_df = train_model(
		dataset=dataset,
		random_state=args.random_state,
		n_estimators=args.n_estimators,
	)

	model_out_path = Path(args.model_out)
	model_out_path.parent.mkdir(parents=True, exist_ok=True)

	joblib.dump(
		{
			"model": model,
			"label_encoder": label_encoder,
			"features": FEATURE_COLUMNS,
			"target": TARGET_COLUMN,
			"classes": list(label_encoder.classes_),
		},
		model_out_path,
	)

	print(f"Dataset rows used: {len(dataset)}")
	print(f"Model saved to: {model_out_path}")
	print("\nClassification report:\n")
	print(report)
	print("Confusion matrix:\n")
	print(matrix_df)


if __name__ == "__main__":
	main()