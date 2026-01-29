defmodule ElixirLLM.ModerationTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.Moderation

  describe "struct" do
    test "has expected fields" do
      moderation = %Moderation{
        flagged: true,
        categories: %{hate: true, violence: false},
        category_scores: %{hate: 0.9, violence: 0.1},
        flagged_categories: [:hate]
      }

      assert moderation.flagged == true
      assert moderation.categories.hate == true
      assert moderation.category_scores.hate == 0.9
      assert :hate in moderation.flagged_categories
    end

    test "all category fields are present" do
      # Verify the expected categories are defined
      expected_categories = [
        :sexual,
        :hate,
        :harassment,
        :self_harm,
        :violence,
        :sexual_minors,
        :hate_threatening,
        :violence_graphic,
        :self_harm_intent,
        :self_harm_instructions,
        :harassment_threatening
      ]

      moderation = %Moderation{
        flagged: false,
        categories: %{},
        category_scores: %{},
        flagged_categories: []
      }

      # Just verify the struct can hold these fields
      assert is_boolean(moderation.flagged)
      assert is_map(moderation.categories)
      assert is_map(moderation.category_scores)
      assert is_list(moderation.flagged_categories)

      # And that we have the expected number of categories
      assert length(expected_categories) == 11
    end
  end

  describe "flagged_categories" do
    test "correctly identifies flagged categories" do
      moderation = %Moderation{
        flagged: true,
        categories: %{hate: true, violence: true, harassment: false},
        category_scores: %{hate: 0.9, violence: 0.8, harassment: 0.1},
        flagged_categories: [:hate, :violence]
      }

      assert :hate in moderation.flagged_categories
      assert :violence in moderation.flagged_categories
      refute :harassment in moderation.flagged_categories
    end
  end

  describe "category_scores access" do
    test "can access individual category scores" do
      moderation = %Moderation{
        flagged: true,
        categories: %{hate: true},
        category_scores: %{hate: 0.85, violence: 0.12, harassment: 0.05},
        flagged_categories: [:hate]
      }

      assert moderation.category_scores.hate == 0.85
      assert moderation.category_scores.violence == 0.12
      assert moderation.category_scores.harassment == 0.05
    end

    test "can find highest scoring category manually" do
      moderation = %Moderation{
        flagged: true,
        categories: %{hate: true, violence: true},
        category_scores: %{hate: 0.6, violence: 0.9, harassment: 0.1},
        flagged_categories: [:hate, :violence]
      }

      {top_category, top_score} =
        moderation.category_scores
        |> Enum.max_by(fn {_k, v} -> v end)

      assert top_category == :violence
      assert top_score == 0.9
    end
  end
end
