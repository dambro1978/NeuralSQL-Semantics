# NeuroSQL-Semantics
A Symbolic AI &amp; Semantic Knowledge Graph engine built entirely in MySQL. Features KNN clustering, vector distance calculation, and etymological regression directly via SQL functions


# 🧠 SemanticGraph-SQL: A Symbolic AI Engine in MySQL

**SemanticGraph-SQL** is an experimental framework that transforms a standard relational database into a semantic knowledge engine. Using **pure SQL**, this system models words as nodes in a multi-dimensional graph, allowing for vector distance calculations, K-Nearest Neighbors (KNN) clustering, and automated concept categorization.

This project demonstrates how classical relational structures can emulate advanced **Natural Language Processing (NLP)** and **Symbolic AI** capabilities without the need for external Python libraries or heavy ML frameworks.

---

## 🚀 Key Features

* **Etymological Root Mapping**: Establishes vertical relationships between words based on shared historical origins.
* **Vector Space Modeling**: Generates feature vectors for every word based on structural attributes (scenario count, synonym density, cluster size).
* **Weighted KNN Algorithm**: A similarity search engine with dynamic weights (Etymology vs. Context) stored in the database.
* **SQL Decision Tree**: An in-engine classifier that categorizes terms into "Action Words," "Primitive Concepts," or "Contextual Hubs" in real-time.
* **Euclidean Distance Calculation**: Measures the geometric distance between semantic vectors to determine conceptual kinship.

---

## 🛠️ Architecture & Logic

The system is built on a three-tier logic:
1.  **Storage Layer**: Core tables for words, etymologies, and synonyms.
2.  **Relational Layer**: Many-to-many pivot tables connecting terms to usage scenarios (context).
3.  **Inference Layer**: Deterministic SQL functions that calculate semantic relevance "on the fly."

---

## 📋 Installation & Setup

1.  Create a MySQL database (v8.0+ recommended for JSON and CTE support).
2.  Execute the provided `SemanticGraphSQL_Complete.sql` script to generate the schema, indexes, and functions.
3.  Populate the `words`, `etymology`, and `scenario` tables with your data.
4.  **Synchronize the Vector Space**:
    Run the following procedure to populate the latent vector table:
    ```sql
    CALL sync_word_vectors();
    ```

---

## 🔍 Usage Examples

### 1. Similarity Search (KNN)
Find the top 5 words most similar to "Bravery" based on current learning weights:
```sql
SELECT knn_evolved_w('bravery', 5);
